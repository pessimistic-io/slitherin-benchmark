// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "./ReentrancyGuard.sol";
import "./DegenPoolManagerSettings.sol";
import "./IDegenPoolManager.sol";
import "./IDegenBase.sol";
import "./IReader.sol";

/**
 * @title DegenPoolManager
 * @author balding-ghost
 * @notice The DegenPoolManager contract is used to handle the funds (similar the the VaultManager contract).  The contract handles liquidations and position closures. The contract also handles the fees that are paid to the protocol and the liquidators. The contract also handles the payouts of the players. It is generally the contract where most is configured and most payout/liquidation logic is handled.
 */
contract DegenPoolManager is IDegenPoolManager, DegenPoolManagerSettings, ReentrancyGuard {
  IReader public immutable reader;

  // this configuration sets the max budget for losses before the contract pauses itself partly. it is sort of the credit line the contract has (given by the DAO) that the contract has to stay within. if the contract exceeds this budget it will stop accepting new positions and will only liquidate positions. this is to prevent the contract from going bankrupt suddenly. If the degen game is profitable (and the profits are collected by the vault) the budget will increase. In this way the value set/added to this value act as the 'max amount of losses possible'. The main purpose of this mechanism is to prevent draining of the vault. It is true that degen can still lose incredibly much if the game is profitable for years and suddently all historical profits are lost in a few  hours. To prevetn this the DAO can decrement so that the budget is reset.
  uint256 public maxLossesAllowedStableTotal;

  // total amount of theoretical bad debt that wlps have endured (not real just metric of bad/inefficient liquidation) in the period
  // this value can be used for seperating wlp profits, bribes, feecollector etc (if we want to)
  uint256 public totalTheoreticalBadDebtUsdPeriod;

  // total amount of escrowed tokens in the contract (of openPositions)
  uint256 public totalActiveMarginInUsd;

  // liquidation threshold is the threshold at which a position can be liquidated (margin level of the position)
  uint256 public liquidationThreshold;

  // amount of tokens escrowed per player (of openOrders and openPositions)
  mapping(address => uint256) public playerMarginInUsd;

  // amount of tokens liquidators can claim as a reward for liquidating positions
  mapping(address => uint256) public liquidatorFeesUsd;

  // max percentage of the margin amount that can be paid as a liquidation fee to liquidator, scaled 1e6
  uint256 public maxLiquidationFee;

  // min percentage of the margin amount that can be paid as a liquidation fee to liquidator, scaled 1e6
  uint256 public minLiquidationFee;

  uint256 public interestLiquidationFee;

  constructor(
    address _vaultAddress,
    address _swap,
    address _reader,
    bytes32 _pythAssetId,
    address _admin,
    address _stableCoinAddress,
    uint256 _decimalsStableCoin
  )
    DegenPoolManagerSettings(
      _vaultAddress,
      _swap,
      _pythAssetId,
      _admin,
      _stableCoinAddress,
      _decimalsStableCoin
    )
  {
    reader = IReader(_reader);
  }

  /// @notice lets vault get wager amount from escrowed tokens
  /// @param _token one of the whitelisted tokens which is collected in settings
  /// @param _amount the amount of token
  function getEscrowedTokens(address _token, uint256 _amount) public {
    require(msg.sender == address(vault), "DegenPoolManager: only vault");
    IERC20(_token).transfer(address(vault), _amount);
  }

  function transferInMarginUsdc(address _player, uint256 _marginAmountUsdc) external onlyDegenGame {
    uint256 _marginAmountUsd;
    unchecked {
      _marginAmountUsd = _marginAmountUsdc * VAULT_SCALING_INCREASE_FOR_USD;
      totalActiveMarginInUsd += _marginAmountUsd;
      playerMarginInUsd[_player] += _marginAmountUsd;
    }
  }

  /**
   * @notice this function is called when a position is closed. it calculates the net profit/loss of the position and credits the player with the profit/loss minus the protocol fee.
   * @dev the protocol fee is calculated based on the size of the position, the duration of the position and the roi of the position.
   * @param _positionKey the key of the position
   * @param _position the position info
   * @param _caller the caller of the position
   * @param _interestFunding the total funding rate paid by the position
   * @return closedPosition_ the closed position info
   */
  function closePosition(
    bytes32 _positionKey,
    PositionInfo memory _position,
    address _caller,
    uint256 _assetPrice,
    uint256 _interestFunding,
    int256 _pnlUsd,
    bool _isPositionValueNegative
  )
    external
    onlyDegenGame
    returns (
      ClosedPositionInfo memory closedPosition_,
      uint256 marginAssetAmount_,
      uint256 feesPaid_
    )
  {
    if (_pnlUsd > 0) {
      // pnl is positive, position is closed in profit
      (closedPosition_, marginAssetAmount_, feesPaid_) = _closePositionInProfit(
        _position,
        _positionKey,
        _caller,
        _assetPrice,
        _interestFunding,
        _pnlUsd
      );
    } else {
      // pnl is negative, position is closed in loss
      (closedPosition_, marginAssetAmount_, feesPaid_) = _closePositionInLoss(
        _positionKey,
        _caller,
        _assetPrice,
        _position.marginAmountUsd,
        _interestFunding,
        _pnlUsd,
        _position.marginAsset, // payout in stables
        _isPositionValueNegative
      );
    }

    return (closedPosition_, marginAssetAmount_, feesPaid_);
  }

  /**
   * @notice this function is called when a position is liquidated.
   * @param _positionKey the key of the position
   * @param _player the player of the position
   * @param _liquidator the liquidator of the position
   * @param _marginAmountUsd the margin amount of the position
   * @param _interestFunding the total funding rate paid by the position
   * @param _assetPrice the price of the asset at the time of closing
   * @param _INT_pnlUsd the pnl of the position including interest paid/due
   * @return closedPosition_ the closed position info
   */
  function _processLiquidationClose(
    bytes32 _positionKey,
    address _player,
    address _liquidator,
    uint256 _marginAmountUsd,
    uint256 _interestFunding,
    uint256 _assetPrice,
    int256 _INT_pnlUsd,
    bool _isPositionValueNegative,
    address _marginAsset
  ) internal returns (ClosedPositionInfo memory closedPosition_, uint256 protocolProfitUsd_) {
    _takeUsdMarginOfPlayer(_player, _marginAmountUsd);

    closedPosition_.player = _player;
    closedPosition_.liquidatorAddress = _liquidator;
    // if payoutInStables is true, the player margined/wagered in stables, so we will pay them out in stables (also  they will get their margin back in stables). If payoutInStables is false, the player margined/wagered in the asset of the contract, so we will pay them out in the asset of the contract (also they will get their margin back in the asset of the contract)
    closedPosition_.marginAsset = _marginAsset;
    closedPosition_.pnlIsNegative = true;
    closedPosition_.timestampClosed = uint32(block.timestamp);
    closedPosition_.priceClosed = uint96(_assetPrice);
    closedPosition_.totalFundingRatePaidUsd = uint96(_interestFunding);
    // note totalPayoutUsd could be denominated in stables or asset, if payout is in stables it is denominated in stables, if payout is in asset it is denominated in asset
    // note margin is always in usd
    closedPosition_.pnlUsd = _INT_pnlUsd;

    uint256 liquidatorFeeUsd_;
    uint256 theoreticalBadDebtUsd_;
    if (_isPositionValueNegative) {
      // the position liquidated from interest funding
      unchecked {
        liquidatorFeeUsd_ = (_marginAmountUsd * interestLiquidationFee) / BASIS_POINTS;
        protocolProfitUsd_ = _marginAmountUsd - liquidatorFeeUsd_;
      }
    } else {
      assert(_INT_pnlUsd < 0); // if liquidated but not isPositionValueNegative, pnl must be negative
      (liquidatorFeeUsd_, theoreticalBadDebtUsd_) = computeLiquidationReward(
        _marginAmountUsd - _interestFunding, // this wont revert because the position value is not negative
        uint256(-1 * _INT_pnlUsd)
      );
      protocolProfitUsd_ = _marginAmountUsd - liquidatorFeeUsd_;
    }

    closedPosition_.liquidationFeePaidUsd = uint96(liquidatorFeeUsd_);

    // position is liquidated so there is no intereset funding paid, (all margin - liquidator fee) is profit for the protocol
    unchecked {
      liquidatorFeesUsd[_liquidator] += liquidatorFeeUsd_;
      // note theoretical debt isn't real debt, it is the difference between the margin amount and the negative pnl of the position (this only is non zero if the position was liquidated at a point where the margin was worth less as the PNL). it is more an indicator of inefficiency of the liquidation mechanism.
      totalTheoreticalBadDebtUsdPeriod += theoreticalBadDebtUsd_;
    }

    emit PositionLiquidated(
      _positionKey,
      _marginAmountUsd,
      protocolProfitUsd_,
      liquidatorFeeUsd_,
      theoreticalBadDebtUsd_,
      _isPositionValueNegative
    );

    return (closedPosition_, protocolProfitUsd_);
  }

  function processLiquidationClose(
    bytes32 _positionKey,
    address _player,
    address _liquidator,
    uint256 _marginAmountUsd,
    uint256 _interestFunding,
    uint256 _assetPrice,
    int256 _INT_pnlUsd,
    bool _isPositionValueNegative,
    address _marginAsset
  ) external onlyDegenGame returns (ClosedPositionInfo memory) {
    (
      ClosedPositionInfo memory closedPosition_,
      uint256 protocolProfitUsd_
    ) = _processLiquidationClose(
        _positionKey,
        _player,
        _liquidator,
        _marginAmountUsd,
        _interestFunding,
        _assetPrice,
        _INT_pnlUsd,
        _isPositionValueNegative,
        _marginAsset
      );

    uint256 profitAmountInStable_ = (protocolProfitUsd_) / additionalPrecisionComparedToStableCoin;
    // wager asset has already swapped to stable
    _payout(_player, address(stableCoin), 0, profitAmountInStable_);
    return closedPosition_;
  }

  /**
   * @notice this function is part of the liquidation incentive mechanism.its purpose is to calculate how much the liquidator will receive as a reward for liquidating a position.
   * @dev the reward is calculated as a percentage of the margin amount of the position. the percentage is calculated based on the distance between the liquidation threshold and the effective margin level of the position.
   * @dev the closer the liquidator is to the liquidation threshold, the higher the reward will be.
   * @param _marginAmountUsd amount of margin the position had in usd
   * @param _pnlUsd amount of negative pnl the position had (including interest) in usd
   * @return liquidatorFeeUsd_ the amount of tokens the liquidator will receive as a reward for liquidating the position
   * @return theoreticalBadDebtUsd_ the amount of tokens that on paper have been lost by the protocol. this is the difference between the margin amount and the negative pnl of the position (this only is non zero if the position was liquidated at a point where the margin was worth less as the PNL)
   */
  function computeLiquidationReward(
    uint256 _marginAmountUsd,
    uint256 _pnlUsd
  ) public view returns (uint256 liquidatorFeeUsd_, uint256 theoreticalBadDebtUsd_) {
    // compute the liquidation threshold of the position.
    uint256 liquidationMarginLevel_ = (_marginAmountUsd * liquidationThreshold) / BASIS_POINTS;

    require(
      _pnlUsd >= liquidationMarginLevel_,
      "DegenPoolManager: margin amount cannot be smaller as the negative pnl in liquidation"
    );

    /**
     * If a user is liquidated the whole margin amount is 'confiscated' by the protocol. The majority of this margin amount will go to the protocols asset pool which took on the risk of the position. A small percentage of the margin amount will go to the liquidator as a reward for liquidating the position.
     *
     * If the liquidator liquidates the position at the liquidation threshold, the liquidator will receive the maximum reward. If the liquidator liquidates the position at a point where it could have been more negative, the liquidator will receive a smaller reward. If the liquidator liquidates the position at a point where it the negative pnl exceeded the margin amount, the liquidator will receive the minimum reward. If the liquidation is in between the threshold and the point where the negative pnl exceeded the margin amount, the liquidator will receive a reward that is between the minimum and maximum reward (linear formula).
     *
     * Example a 1 ETH short position with 500x leverage and a liquidation threshold of 10%. Min liquidation fee is 5% and max liquidation fee is 10%.
     *
     * This means that if the pnl of the position was -0.9 ETH, the position would be liquidated.
     * 1. If the liquidator liquidates the position at PNL of -0.9 ETH, the liquidator will receive 10% of the margin amount as a reward and the protocol(0.1 ETH) the protocl will receive 0.9ETH.
     * 2. If the liquidator liquidates the position at PNL of -0.95 ETH, the liquidator will receive 7.5% of the margin amount as a reward and the protocol(0.075 ETH) the protocl will receive 0.925ETH.
     * 3. If the liquidator liquidates the position at PNL of -1 ETH, the liquidator will receive 5% of the margin amount as a reward and the protocol(0.05 ETH) the protocl will receive 0.95ETH.
     */

    // calculate the liquidation distance, so this is the distance between the liquidation threshold and the effective margin level of the position
    // this cannot underflow otherwise the position wasn't liquidatable in the first place (and it would have failed the require in the liquidate function)

    unchecked {
      uint256 liquidationDistance_ = _pnlUsd - liquidationMarginLevel_;

      uint256 thresHoldDistance_ = _marginAmountUsd - liquidationMarginLevel_;

      if (liquidationDistance_ == 0) {
        // the liquidator has liquiated the position at the liquidation threshold this is the best result (so position was liquidated on the exact cent it became liquitable)
        liquidatorFeeUsd_ = (_marginAmountUsd * maxLiquidationFee) / BASIS_POINTS;
        theoreticalBadDebtUsd_ = 0;
      } else if (liquidationDistance_ >= thresHoldDistance_) {
        // the liquidator has liquiated the position at the point where it couldn't have been any more negative
        liquidatorFeeUsd_ = (_marginAmountUsd * minLiquidationFee) / BASIS_POINTS;
        theoreticalBadDebtUsd_ = liquidationDistance_ - thresHoldDistance_;
      } else {
        // the liquidator has liquidated the position between the threshold and the point where it couldn't have been any more negative
        // Compute slope of the line scaled by BASIS_POINTS
        uint256 slope_ = ((maxLiquidationFee - minLiquidationFee) * BASIS_POINTS) /
          thresHoldDistance_;
        uint256 rewardPercentage_ = maxLiquidationFee -
          ((slope_ * liquidationDistance_) / BASIS_POINTS); // Remember to scale down after multiplication
        liquidatorFeeUsd_ = (_marginAmountUsd * rewardPercentage_) / BASIS_POINTS;
        theoreticalBadDebtUsd_ = 0;
      }
    }
  }

  function claimLiquidationFees() external nonReentrant {
    uint256 liquidatorFeeUsd_ = liquidatorFeesUsd[msg.sender];

    liquidatorFeeUsd_ = liquidatorFeeUsd_ / additionalPrecisionComparedToStableCoin;
    liquidatorFeesUsd[msg.sender] = 0;
    stableCoin.transfer(msg.sender, liquidatorFeeUsd_);
    emit ClaimLiquidationFees(liquidatorFeeUsd_);
  }

  function incrementMaxLossesBuffer(uint256 _maxLossesIncrease) external onlyAdmin {
    maxLossesAllowedStableTotal += _maxLossesIncrease;
    emit IncrementMaxLosses(_maxLossesIncrease, maxLossesAllowedStableTotal);
  }

  function decrementMaxLossesBuffer(uint256 _maxLossesDecrease) external onlyAdmin {
    require(
      _maxLossesDecrease <= maxLossesAllowedStableTotal,
      "DegenPoolManager: invalid decrease"
    );
    maxLossesAllowedStableTotal -= _maxLossesDecrease;
    emit DecrementMaxLosses(_maxLossesDecrease, maxLossesAllowedStableTotal);
  }

  function setMaxLiquidationFee(uint256 _maxLiquidationFee) external onlyAdmin {
    require(_maxLiquidationFee <= BASIS_POINTS, "DegenPoolManager: invalid fee");
    maxLiquidationFee = _maxLiquidationFee;
    emit SetMaxLiquidationFee(_maxLiquidationFee);
  }

  function setMinLiquidationFee(uint256 _minLiquidationFee) external onlyAdmin {
    require(_minLiquidationFee <= BASIS_POINTS, "DegenPoolManager: invalid fee");
    minLiquidationFee = _minLiquidationFee;
    emit SetMinLiquidationFee(_minLiquidationFee);
  }

  function setInterestLiquidationFee(uint256 _interestLiquidationFee) external onlyAdmin {
    require(_interestLiquidationFee <= BASIS_POINTS, "DegenPoolManager: invalid fee");
    interestLiquidationFee = _interestLiquidationFee;
    emit SetMinLiquidationFee(_interestLiquidationFee);
  }

  function setLiquidationThreshold(uint256 _liquidationThreshold) external onlyAdmin {
    require(_liquidationThreshold <= BASIS_POINTS, "DegenPoolManager: invalid threshold");
    IDegenBase(degenGameContract).setLiquidationThreshold(_liquidationThreshold);
    liquidationThreshold = _liquidationThreshold;
    emit SetLiquidationThreshold(_liquidationThreshold);
  }

  function returnVaultReserveInAsset() external view returns (uint256 vaultReserveUsd_) {
    // fetch the amount of usd reserve in the vault, note this is scaled 1e30, so 1 usd is 1e30
    vaultReserveUsd_ = vault.getReserve() / 1e12; // 1e12 is to scale back 1e30 to 1e18 todo add constant
    require(vaultReserveUsd_ != 0, "DegenPoolManager: vault reserve is 0");
  }

  // internal functions
  /**
   * @notice this function is called when a position is closed in profit. it calculates the net profit of the position and credits the player with the profit minus the protocol fee.
   * @dev the protocol fee is calculated based on the size of the position, the duration of the position and the roi of the position.
   * @param _positionKey the key of the position
   * @param _player the player of the position
   * @param _assetPrice the price of the asset at the time of closing
   * @param _interestFunding the total funding rate paid by the position
   * @param _pnlUsd the pnl of the position including interest paid/due
   * @return closedPosition_ the closed position info
   */
  function _closePositionInProfit(
    PositionInfo memory _position,
    bytes32 _positionKey,
    address _player,
    uint256 _assetPrice,
    uint256 _interestFunding,
    int256 _pnlUsd
  )
    internal
    returns (
      ClosedPositionInfo memory closedPosition_,
      uint256 marginAssetAmount_,
      uint256 feesPaid_
    )
  {
    // credit the player with their margin
    _takeUsdMarginOfPlayer(_player, _position.marginAmountUsd);

    // calculate the net profit of the position in usd (doesn't matter so far if the player is going to be paid out in the asset or not, we will convert it later)
    (uint256 pnlMinusFeeAmountUsd_, uint256 closeFeeProtocolUsd_) = _calculateNetProfitOfPosition(
      _position.positionSizeUsd,
      _position.priceOpened,
      _assetPrice,
      _position.maxPositionProfitUsd,
      _pnlUsd
    );

    uint96 payoutMinusAllFees_ = 0;
    if (_position.marginAmountUsd + uint96(pnlMinusFeeAmountUsd_) > uint96(_interestFunding)) {
      payoutMinusAllFees_ =
        _position.marginAmountUsd +
        uint96(pnlMinusFeeAmountUsd_) -
        uint96(_interestFunding);
    }

    closedPosition_.player = _player;

    closedPosition_.timestampClosed = uint32(block.timestamp);
    closedPosition_.marginAsset = _position.marginAsset;
    closedPosition_.priceClosed = uint96(_assetPrice);

    closedPosition_.totalFundingRatePaidUsd = uint96(_interestFunding);
    closedPosition_.closeFeeProtocolUsd = uint96(closeFeeProtocolUsd_);

    closedPosition_.totalPayoutUsd = uint96(pnlMinusFeeAmountUsd_);
    // note if the player has marginned in the asset, the player will have returned the asset, however we do registered the margin returned in usd
    closedPosition_.pnlUsd = _pnlUsd;

    uint256 payoutAmountInStable_ = (payoutMinusAllFees_) / additionalPrecisionComparedToStableCoin;
    uint256 marginAmountInStable_ = _position.marginAmountUsd /
      additionalPrecisionComparedToStableCoin;

    (marginAssetAmount_, feesPaid_) = _payout(
      _player,
      _position.marginAsset,
      payoutAmountInStable_,
      marginAmountInStable_
    );
    emit PositionClosedInProfit(_positionKey, pnlMinusFeeAmountUsd_, closeFeeProtocolUsd_);

    return (closedPosition_, marginAssetAmount_, feesPaid_);
  }

  /**
   * @dev Internal function to process a payout to a player.
   * @param _player The address of the player receiving the payout.
   * @param _marginAsset The address of the margin asset involved in the payout.
   * @param payoutAmountInStable_ The payout amount in stable tokens.
   * @param marginAmountInStable_ The margin amount in stable tokens.
   * @return marginAssetAmount_ The amount of margin asset received by the player.
   * @return feesPaid_ The fees paid during the payout process.
   */
  function _payout(
    address _player,
    address _marginAsset,
    uint256 payoutAmountInStable_,
    uint256 marginAmountInStable_
  ) internal returns (uint256 marginAssetAmount_, uint256 feesPaid_) {
    // Check if the payout is allowed based on maximum losses.
    bool isAllowed_ = _updateAndCheckMaxAllowedLoss(marginAmountInStable_, payoutAmountInStable_);

    if (!isAllowed_) {
      // If payout is not allowed, return no margin and no fees paid.
      return (0, 0);
    }

    if (payoutAmountInStable_ == 0) {
      // If the payout amount is zero, perform a pay-in to the vault.
      vault.payin(address(stableCoin), address(this), marginAmountInStable_);
      return (marginAmountInStable_, 0);
    }

    // Perform a payout from the vault.
    vault.payout(
      address(stableCoin),
      address(this),
      marginAmountInStable_,
      address(this),
      payoutAmountInStable_
    );

    if (_marginAsset != address(stableCoin)) {
      // If the margin asset is different from stableCoin, perform a swap.
      stableCoin.transfer(address(swap), payoutAmountInStable_);
      (marginAssetAmount_, feesPaid_) = swap.swapTokens(
        payoutAmountInStable_,
        address(stableCoin),
        _marginAsset,
        _player
      );
    } else {
      // If the margin asset is stableCoin, transfer it directly to the player.
      stableCoin.transfer(_player, payoutAmountInStable_);
      marginAssetAmount_ = payoutAmountInStable_;
      feesPaid_ = 0;
    }
  }

  /**
   * @dev Internal function to update and check the maximum allowed loss budget.
   * @param _marginAmountInStable The margin amount in stable tokens.
   * @param _payoutAmountInStable The payout amount in stable tokens.
   * @return isAllowed_ A boolean indicating whether the payout is allowed based on the maximum losses allowed.
   */
  function _updateAndCheckMaxAllowedLoss(
    uint256 _marginAmountInStable,
    uint256 _payoutAmountInStable
  ) internal returns (bool isAllowed_) {
    if (_payoutAmountInStable > maxLossesAllowedStableTotal) {
      // If the payout exceeds the maximum allowed losses, reset and restrict further actions.
      maxLossesAllowedStableTotal = 0;
      IDegenBase(degenGameContract).setOpenOrderAllowed(false);
      IDegenBase(degenGameContract).setOpenPositionAllowed(false);
      emit MaxLossesAllowedBudgetSpent();
      isAllowed_ = false;
    } else {
      // If the margin amount is greater than the payout amount, it means it's a profit for the protocol.
      // the maxLossesAllowedStableTotal should be increased.
      if (_marginAmountInStable > _payoutAmountInStable) {
        // Calculate the increase in maximum allowed losses budget if the margin is greater than the payout.
        uint256 increaseAmount_ = _marginAmountInStable - _payoutAmountInStable;
        maxLossesAllowedStableTotal += increaseAmount_;
      } else {
        // Calculate the decrease in maximum allowed losses budget if the payout is greater than the margin.
        uint256 decreaseAmount_ = _payoutAmountInStable - _marginAmountInStable;
        maxLossesAllowedStableTotal -= decreaseAmount_;
      }
      isAllowed_ = true;
    }
  }

  /**
   * @notice internal function that scales the target asset to usd amount scaled to 1e18
   * @param _amountOfAsset amount of the asset scaled in the assets decimals
   * @param _assetPrice price of the asset scaled in PRICE_PRECISION
   * @return _amountOfUsd amount of usd scaled in PRICE_PRECISION
   */
  function _targetAssetToUsd(
    uint256 _amountOfAsset,
    uint256 _assetPrice,
    address _wagerAsset
  ) internal view returns (uint256 _amountOfUsd) {
    uint256 decimalsToken_ = vault.tokenDecimals(_wagerAsset);
    unchecked {
      _amountOfUsd = (_amountOfAsset * _assetPrice) / (10 ** decimalsToken_);
    }
  }

  /**
   * @notice this function calculates the net profit of a position. it takes into account the size of the position, the duration of the position and the roi of the position.
   * @dev the roi is calculated as the pnl of the position divided by the margin amount of the position.
   * @dev the roi is then used to calculate the protocol fee. the protocol fee is calculated based on the size of the position, the duration of the position and the roi of the position.
   * @param _positionSizeUsd the size of the position
   * @param _openPrice the open price of the position
   * @param _assetPrice the price of the asset at the time of closing
   * @param _maxPositionProfitUsd the maximum profit the position could have made
   * @param INT_pnlUsd the pnl of the position including interest paid/due
   * @return payoutAmount_ the amount of tokens the player will receive as a payout
   * @return closeFeeProtocolUsd_ the amount of tokens the protocol will receive as a fee
   */
  function _calculateNetProfitOfPosition(
    uint256 _positionSizeUsd,
    uint256 _openPrice,
    uint256 _assetPrice,
    uint256 _maxPositionProfitUsd,
    int256 INT_pnlUsd
  ) internal pure returns (uint256 payoutAmount_, uint256 closeFeeProtocolUsd_) {
    assert(INT_pnlUsd > 0);
    // position in profit, pnl is positive
    uint256 _pnlUsd = uint256(INT_pnlUsd);
    if (_pnlUsd > _maxPositionProfitUsd) {
      _pnlUsd = _maxPositionProfitUsd;
    }

    // calculate the price move percentage of the position
    // _positionSizeUsd should be like 100 00000000 = 100$ and will be div by 1e10 in _calculateProfitFee
    // _priceMovePercentage is like 50000 = 0.05 = 5%, 100000 = 0.1 = 10%
    uint256 _priceMovePercentage = _calculatePriceMovePercentage(_openPrice, _assetPrice);

    _checkIfPriceMoveIsSufficientToClose(_priceMovePercentage);

    // calculate the fee percentage of the position
    uint256 pnlFeePercentage_ = _calculateProfitFee(_priceMovePercentage, _positionSizeUsd);

    // calculate the fee of the position
    closeFeeProtocolUsd_ = (_pnlUsd * pnlFeePercentage_) / SCALE;
    // calculate the payout of the position
    payoutAmount_ = _pnlUsd - closeFeeProtocolUsd_;
  }

  /**
   * @notice this function is called when a position is closed in loss. it calculates the net loss of the position and credits the player with the margin amount left.
   * @dev the margin amount left is the amount of margin that is left after the position is closed. if the position is liquidated, the margin amount left is 0.
   * @param _positionKey the key of the position
   * @param _player the player of the position
   * @param _assetPrice the price of the asset at the time of closing
   * @param _marginAmountUsd the margin amount of the position in usd
   * @param _interestFunding the total funding rate paid by the position
   * @param _pnlUsd the pnl of the position including interest paid/due
   * @param _marginAsset the asset the margin was placed in, should be the asset the user should be paid out in (their remaining margin)
   * @return closedPosition_ the closed position info
   */
  function _closePositionInLoss(
    bytes32 _positionKey,
    address _player,
    uint256 _assetPrice,
    uint256 _marginAmountUsd,
    uint256 _interestFunding,
    int256 _pnlUsd,
    address _marginAsset,
    bool _isPositionValueNegative
  )
    internal
    returns (
      ClosedPositionInfo memory closedPosition_,
      uint256 marginAssetAmount_,
      uint256 feesPaid_
    )
  {
    _takeUsdMarginOfPlayer(_player, _marginAmountUsd);
    uint256 marginLeftUsd_;

    if (_isPositionValueNegative) {
      revert("DegenPoolManager: position has liquidated");
    }
    if (_pnlUsd > 0) {
      revert("DegenPoolManager: position has profit");
    }
    unchecked {
      marginLeftUsd_ = uint256(int256(_marginAmountUsd) - int256(_interestFunding) + _pnlUsd);
    }
    if (marginLeftUsd_ > 0) {
      uint256 payoutAmountInStable_ = marginLeftUsd_ / additionalPrecisionComparedToStableCoin;
      uint256 marginAmountInStable_ = _marginAmountUsd / additionalPrecisionComparedToStableCoin;
      (marginAssetAmount_, feesPaid_) = _payout(
        _player,
        _marginAsset,
        payoutAmountInStable_,
        marginAmountInStable_
      );
    }

    closedPosition_.player = _player;

    closedPosition_.timestampClosed = uint32(block.timestamp);
    closedPosition_.marginAsset = _marginAsset;
    closedPosition_.priceClosed = uint96(_assetPrice);

    closedPosition_.pnlIsNegative = true;
    closedPosition_.totalFundingRatePaidUsd = uint96(_interestFunding);

    closedPosition_.pnlUsd = (_pnlUsd);
    closedPosition_.totalPayoutUsd = (marginLeftUsd_);

    emit PositionClosedInLoss(_positionKey, marginLeftUsd_);

    return (closedPosition_, marginAssetAmount_, feesPaid_);
  }

  function _takeUsdMarginOfPlayer(address _player, uint256 _marginAmountUsd) internal {
    unchecked {
      totalActiveMarginInUsd -= _marginAmountUsd;
      playerMarginInUsd[_player] -= _marginAmountUsd;
    }
  }

  function _checkIfPriceMoveIsSufficientToClose(uint256 _priceMovePercentage) internal pure {
    require(
      _priceMovePercentage >= minPriceMove,
      "DegenPoolManager: price move percentage is too low to close"
    );
  }

  /**
   * @notice Function to calculate the price move percentage.
   * @param _openPrice The open price of the position.
   * @param _closePrice The close price of the position.
   */
  function _calculatePriceMovePercentage(
    uint256 _openPrice,
    uint256 _closePrice
  ) internal pure returns (uint256 priceMovePercentage_) {
    int256 diff_;
    unchecked {
      diff_ = int256(_closePrice) - int256(_openPrice);
      // if the diff is negative, make it positive
      diff_ < 0 ? diff_ = diff_ * -1 : diff_;
      priceMovePercentage_ = (uint256(diff_) * SCALE) / _openPrice;
    }
  }

  /**
   * @notice Function to calculate the shift amount based on the position size.
   * @notice The shift amount is used to shift the fee curve based on the position size.
   * @param _positionSize The size of the position for which the shift amount is calculated.
   */
  function _shiftByPositionSize(uint256 _positionSize) internal pure returns (uint256 result) {
    int256 result_;
    // position size * factor is always greater than -factor since position size is positive, so result_ is always positive
    // factor is constant and _position size can not be greater than the maxPositionSize(constant) so the result is limited
    unchecked {
      result_ = (-factor + (int256(_positionSize) * factor)) / int256(10 ** 13);
    }
    return (uint256(result_));
  }

  /**
   * @notice This function calculates the maximum fee for a position.
   *         The max fee is determined based on the size of the position,
   *         with larger positions incurring higher fees.
   * @param _positionSize The size of the position for which the max fee is calculated.
   * @return  maxFee_ The calculated maximum fee for the given position size.
   */
  function _calculateMaxFee(uint256 _positionSize) internal pure returns (uint256 maxFee_) {
    /**
     * Calculate the difference between max fee at max position size (which is 82% default)
     * and max fee at min position size (which is 50% default)
     */

    uint256 diff_ = maxFeeAtMaxPs - maxFeeAtMinPs;
    uint256 diffScaled_ = diff_ * SCALE * SCALE;
    uint256 positionRange_ = maxPositionSize - minPositionSize;

    // Calculate the fee using linear interpolation
    maxFee_ =
      (diffScaled_ * (_positionSize - minPositionSize)) /
      (positionRange_ * SCALE * SCALE) +
      maxFeeAtMinPs;
  }

  function _calculateProfitFee(
    uint256 _priceMove,
    uint256 _positionSize
  ) internal pure returns (uint256) {
    // convert the position size to 1e8 because the pnl fee model the scaling for usd and percentages are both 1e8 (SCALE). The rest of the contract uses 1e18 for usd and 1e6 for percentages
    _positionSize = _positionSize / 1e10;
    // calculate the max fee
    uint256 maxFeeForPositionSize_ = _calculateMaxFee(_positionSize);

    // calculate the shift amount based on the position size
    // shift amount will be add to the result of the fee calculation to shift the fee curve
    uint256 shiftAmount_ = _shiftByPositionSize(_positionSize);

    // Check if the provided price move is within the specified range
    if (maxPriceMove > _priceMove && _priceMove >= minPriceMove) {
      // Calculate the fee using linear interpolation
      return
        shiftAmount_ +
        maxFeeForPositionSize_ -
        ((maxFeeForPositionSize_ - minFee) * (_priceMove - minPriceMove)) /
        (maxPriceMove - minPriceMove);
    } else {
      // If the price move is out of the specified range, return the min fee
      // it means the price move is greater than the max price move, it should return the min fee
      return minFee;
    }
  }
}

