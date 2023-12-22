// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ECDSA.sol";
import "./IPyth.sol";
import "./PythStructs.sol";
import "./IVault.sol";
import "./IReferralStorage.sol";
import "./SafeERC20.sol";
import "./AccessControlEnumerable.sol";
import "./IDegenPool.sol";
import "./ISecondaryPriceFeed.sol";

contract DegenPool is IDegenPool, AccessControlEnumerable {
  using ECDSA for bytes;
  using SafeERC20 for IERC20;

  IPyth public immutable pyth;
  IVault public immutable vault; /// @notice Vault address
  IERC20 public immutable asset;
  bytes32 public immutable pythAssetId;

  ISecondaryPriceFeed public secondaryPriceFeed;

  uint96 public constant SCALE = 1e6;
  uint96 public constant minFee = 100000; /// @notice The minimum fee percentage 10%
  uint96 public constant minPriceMove = 100; /// @notice The minimum price move percentage
  uint96 public constant maxPriceMove = 100000; /// @notice The maximum price move percentage 10%, The pnl fee will be fixed after this price move, also 10% after this price move
  uint96 public constant maxFeeAtMaxPs = 820000; /// @notice The maximum fee at the maximum position size, occurring at a 0.01% price move, is 82% of the profit.
  uint96 public constant maxFeeAtMinPs = 500000; /// @notice The maximum fee at the minimum position size, occurring at a 0.01% price move, is 50% of the profit.
  uint96 public immutable maxPositionSize;

  // Exposure config
  uint8 public freshness = 15;
  uint96 public maxProfit;
  uint96 public maxExposure;
  uint96 public totalLongExposure;
  uint96 public totalShortExposure;
  uint96 public liquidatorFee = 4e4;
  uint256 public budget; // this configuration sets the max budget for losses before the contract pauses itself partly. it is sort of the credit line the contract has (given by the DAO) that the contract has to stay within. if the contract exceeds this budget it will stop accepting new positions and will only liquidate positions. this is to prevent the contract from going bankrupt suddenly. If the degen game is profitable (and the profits are collected by the vault) the budget will increase. In this way the value set/added to this value act as the 'max amount of losses possible'. The main purpose of this mechanism is to prevent draining of the vault. It is true that degen can still lose incredibly much if the game is profitable for years and suddently all historical profits are lost in a few  hours. To prevetn this the DAO can decrement so that the budget is reset.

  uint96 public bribeRate = 1e4;
  /// @notice Referral storage address
  uint96 public pendingBribe;

  /// @notice Referral storage address
  IReferralStorage public refStore;

  mapping(bytes32 => Position) public positions;
  mapping(address => uint96) public liquidatorFees; /// @notice amount of tokens liquidators can claim as a reward for liquidating positions
  mapping(address => bool) public swapAllowed;
  FundFeeConfig public fundFeeConfig = FundFeeConfig(25, 180, 60);

  uint96 public minPositionSize = 1 * SCALE; /// @notice The minimum position size in dollar value 1$ * 1e6
  uint32 public pythUpdateFee = 1;
  uint16 public minPositionDuration = 60; /// @notice The minimum position duration in seconds
  uint16 public minLeverage = 100; /// @notice The minimum leverage
  uint16 public maxLeverage = 1000; /// @notice The maximum leverage
  uint96 public minWager = 98e4; /// @notice The minimum wager amount 0,98$

  uint64 pairIndex;
  bool public isSecondaryEnabled;

  // Roles
  bytes32 public constant OPERATOR = bytes32(keccak256("OPERATOR"));
  bytes32 public constant KEEPER = bytes32(keccak256("KEEPER"));
  bytes32 public constant CONTROLLER = bytes32(keccak256("CONTROLLER"));

  modifier onlyPosOwnerAndNotClosed(bytes32 id, bool isSwap) {
    // Check if it's a swap or a regular close
    if (isSwap) {
      // Require that the sender has the OPERATOR role for swaps
      require(hasRole(OPERATOR, msg.sender), "only swap");
    } else {
      // Require that the sender is the owner of the position
      require(msg.sender == positions[id].player, "Invalid position owner");
    }

    // Require that the position is not already closed
    require(!positions[id].close, "Position already closed");

    // Continue with the execution of the function
    _;
  }

  constructor(
    IPyth pyth_,
    IReferralStorage refStore_,
    bytes32 pythAssetId_,
    address asset_,
    address controller_,
    address vault_,
    uint64 pairIndex_,
    uint96 maxPositionSize_,
    uint96 budget_,
    uint96 maxExposure_
  ) {
    pyth = pyth_;
    refStore = refStore_;
    pythAssetId = pythAssetId_;
    asset = IERC20(asset_);
    vault = IVault(vault_);
    pairIndex = pairIndex_;
    maxPositionSize = maxPositionSize_;
    budget = budget_;
    maxExposure = maxExposure_;
    _grantRole(DEFAULT_ADMIN_ROLE, controller_);
    _grantRole(CONTROLLER, controller_);
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(CONTROLLER, msg.sender);
  }

  function setExpoConf(uint96 maxExpo) external onlyRole(CONTROLLER) {
    // Set the maximum exposure limit
    maxExposure = maxExpo;

    // Emit an event to log the configuration change
    emit SetExpoConfig(maxExpo);
  }

  function setSecondaryPriceFeed(
    ISecondaryPriceFeed secondaryPriceFeed_
  ) external onlyRole(CONTROLLER) {
    // Set the secondary price feed contract address
    secondaryPriceFeed = secondaryPriceFeed_;

    // Emit an event to log the change of the secondary price feed contract
    emit SetSecondaryPriceFeed(address(secondaryPriceFeed_));
  }

  function updateBudget(uint96 newBudget) external onlyRole(CONTROLLER) {
    // Update the budget with the new value
    budget = newBudget;

    // Emit an event to log the budget update
    emit UpdateBudget(newBudget);
  }

  function updateMaxProfit(uint96 newMaxProfit) external onlyRole(CONTROLLER) {
    // Update the maximum profit limit with the new value
    maxProfit = newMaxProfit;

    // Emit an event to log the update of the maximum profit limit
    emit UpdateMaxProfit(newMaxProfit);
  }

  function updateBribeRate(uint96 newBribeRate) external onlyRole(CONTROLLER) {
    // Update the bribe rate with the new value
    bribeRate = newBribeRate;

    // Emit an event to log the update of the bribe rate
    emit UpdateBribeRate(newBribeRate);
  }

  function updateFreshness(uint8 newFreshness) external onlyRole(CONTROLLER) {
    // Update the freshness value with the new value
    freshness = newFreshness;

    // Emit an event to log the update of the freshness value
    emit UpdateFreshness(newFreshness);
  }

  function updateLiquidatorFee(uint96 newLiquidatorFee) external onlyRole(CONTROLLER) {
    // Update the liquidator fee with the new value
    liquidatorFee = newLiquidatorFee;

    // Emit an event to log the update of the liquidator fee
    emit UpdateLiquidatorFee(newLiquidatorFee);
  }

  function updatePythUpdateFee(uint32 newPythUpdateFee) external onlyRole(CONTROLLER) {
    // Update the Pyth update fee with the new value
    pythUpdateFee = newPythUpdateFee;

    // Emit an event to log the update of the Pyth update fee
    emit UpdatePythUpdateFee(newPythUpdateFee);
  }

  function updatePairIndex(uint64 newPairIndex) external onlyRole(CONTROLLER) {
    // Update the pair index with the new value
    pairIndex = newPairIndex;

    // Emit an event to log the update of the pair index
    emit UpdatePairIndex(newPairIndex);
  }

  function updateFundFeeConfig(
    uint16 rate,
    uint16 buffer,
    uint16 period
  ) external onlyRole(CONTROLLER) {
    // Check if the rate is within a valid range
    require(rate <= SCALE, "Invalid rate");

    // Check if the period is a positive value
    require(period > 0, "Invalid period");

    // Create a new FundFeeConfig struct with the provided values
    fundFeeConfig = FundFeeConfig(rate, buffer, period);

    // Emit an event to log the update of the fund fee configuration
    emit UpdateFundFeeConfig(fundFeeConfig);
  }

  function updateMinPositionDuration(uint16 newMinPositionDuration) external onlyRole(CONTROLLER) {
    // Update the minimum position duration with the new value
    minPositionDuration = newMinPositionDuration;

    // Emit an event to log the update of the minimum position duration
    emit UpdateMinPosDuration(newMinPositionDuration);
  }

  function updateMinMaxLeverage(
    uint16 newMinLeverage,
    uint16 newMaxLeverage
  ) external onlyRole(CONTROLLER) {
    // Check if the new minimum leverage is less than or equal to the new maximum leverage
    require(newMinLeverage <= newMaxLeverage, "Invalid leverage");

    // Check if the new minimum leverage is greater than 1
    require(newMinLeverage > 1, "Invalid leverage");

    // Update the minimum and maximum leverage values with the new values
    minLeverage = newMinLeverage;
    maxLeverage = newMaxLeverage;

    // Emit an event to log the update of the minimum and maximum leverage values
    emit UpdateMinMaxLeverage(newMinLeverage, newMaxLeverage);
  }

  function updateMinWager(uint96 newMinWager) external onlyRole(CONTROLLER) {
    // Check if the new minimum wager is greater than 500000 (0,5$)
    require(newMinWager > 50e4, "Invalid wager");

    // Update the minimum wager with the new value
    minWager = newMinWager;

    // Emit an event to log the update of the minimum wager
    emit UpdateMinWager(newMinWager);
  }

  function setSwapAllowed(address user, bool allowed) external {
    // Check if the sender is the same as the user whose swap permission is being modified
    require(msg.sender == user, "Invalid user");

    // Set the swap permission for the specified user
    swapAllowed[user] = allowed;

    // Emit an event to log the change in swap permission for the user
    emit SwapAllowed(user, allowed);
  }

  function setSecondaryEnabled(bool isEnabled) external onlyRole(CONTROLLER) {
    // Set the secondary functionality's enabled state
    isSecondaryEnabled = isEnabled;

    // Emit an event to log the change in the secondary functionality's enabled state
    emit SecondaryEnabled(isEnabled);
  }

  function getPosition(bytes32 id) public view returns (Position memory) {
    // Retrieve and return the Position struct associated with the provided ID
    return positions[id];
  }

  function hashOrder(Order calldata order) public view returns (bytes32) {
    // Check if the order's validUntil timestamp is in the future
    require(order.validUntil > block.timestamp, "ValidUntil too early");

    // Hash the order's data using keccak256 and return the resulting bytes32 value
    return keccak256(abi.encode(order));
  }

  function verify(Order calldata order, bytes calldata signature_) public view returns (bool) {
    // Check if the order has not expired
    require(order.validUntil > block.timestamp, "Order is expired");

    // Calculate the Ethereum signed message hash of the order and then recover the signer's address
    address signer = ECDSA.recover(
      ECDSA.toEthSignedMessageHash(keccak256(abi.encode(order))),
      signature_
    );

    // Compare the recovered signer's address with the order's player address to verify the signature
    return signer == order.player;
  }

  function updatePrice(bytes[] calldata priceUpdateData) internal returns (uint64) {
    // Update the price feeds with the provided data and send the specified value as an Ether transfer
    pyth.updatePriceFeeds{value: pythUpdateFee}(priceUpdateData);

    // Retrieve the latest price data from the Pyth contract with a freshness constraint
    PythStructs.Price memory price = pyth.getPriceNoOlderThan(pythAssetId, freshness);

    require(price.price > 0, "Price should not below 0");

    uint256 PRICE_PRECISION = 1e8;
    uint256 priceScaled;
    if (price.expo >= 0) {
      uint256 exponent = uint256(uint32(price.expo));
      priceScaled = uint256(uint64(price.price)) * PRICE_PRECISION * (10 ** exponent);
    } else {
      uint256 exponent = uint256(uint32(-price.expo));
      priceScaled = (uint256(uint64(price.price)) * PRICE_PRECISION) / (10 ** exponent);
    }

    if (priceScaled > type(uint64).max) {
      revert("Price out of range");
    }
    // Return the updated price as a uint64 value
    return uint64(priceScaled);
  }

  function getPriceFromSecondary() internal returns (uint64) {
    // Retrieve the price for the specified pair index from the secondary price feed
    uint256 price = secondaryPriceFeed.getPrice(pairIndex);
    if (price > type(uint64).max) {
      revert("Price out of range");
    }
    return uint64(price);
  }

  /// @notice Allows the vault to retrieve escrowed tokens.
  /// @param token The address of one of the whitelisted tokens collected in settings.
  /// @param amount The amount of tokens to be retrieved.
  function getEscrowedTokens(address token, uint256 amount) public {
    // Ensure that only the vault is allowed to call this function
    address vaultAddress = address(vault);
    require(msg.sender == vaultAddress, "DegenPoolManager: Only vault can call this");

    // Transfer the specified amount of tokens to the vault
    IERC20(token).safeTransfer(vaultAddress, amount);
  }

  function _decreaseExposure(bool long, uint96 size) internal {
    unchecked {
      if (long) {
        // decrease the total long exposure
        totalLongExposure -= size;
      } else {
        // decrease the total short exposure
        totalShortExposure -= size;
      }
    }
  }

  function _increaseExposure(bool long, uint96 size) internal {
    unchecked {
      if (long) {
        // increase the total long exposure
        totalLongExposure += size;
        require(totalLongExposure <= maxExposure, "Degen: max exposure reached");
      } else {
        // increase the total short exposure
        totalShortExposure += size;
        require(totalShortExposure <= maxExposure, "Degen: max exposure reached");
      }
    }
  }

  function setRefReward(address player, uint96 amount) internal returns (uint96 reward) {
    // Check if the provided amount is greater than zero
    if (amount > 0) {
      // Calculate the reward by dividing the amount by 100 and then multiplying it by 100
      reward = uint96(refStore.setReward(player, address(asset), uint256(amount / 1e2))) * 1e2;
    }
  }

  function execute(
    bytes[] calldata priceData,
    Order calldata order,
    bytes calldata sig
  ) external onlyRole(KEEPER) {
    // Verify the order's signature
    require(verify(order, sig), "Order is not verified");

    // Calculate a unique ID for the position
    bytes32 id = keccak256(sig);

    // Check if a position with the same ID already exists
    require(positions[id].player == address(0), "Position already created");
    // Update the price based on the provided price data
    uint64 price = updatePrice(priceData);

    uint64 maxPrice = (order.maxPrice == 0) ? type(uint64).max : order.maxPrice;

    require(price >= order.minPrice, "Price outside of min limits");
    require(price <= maxPrice, "Price outside of max limits");

    // Calculate the position size
    uint96 size = (order.col * order.lev);

    // Check if the position size exceeds the maximum allowed
    require(size <= maxPositionSize, "Position size too high");

    // Check if the collateral amount in the order is greater than or equal to the minimum wager
    require(order.col >= minWager, "Wager too low");

    // Check if the leverage in the order is greater than or equal to the minimum leverage
    require(order.lev >= minLeverage, "Leverage too low");

    // Check if the leverage in the order is within the maximum allowed range
    require(order.lev <= maxLeverage, "Leverage too high");

    // Transfer USDC.e collateral from the player to this contract
    IERC20(asset).safeTransferFrom(order.player, address(this), order.col);

    // Calculate the bust price and margin
    uint64 bustPrice = price;
    uint64 margin = price / order.lev;
    margin -= margin / 10;

    // Adjust the bust price based on the order's direction (long or short)
    order.long ? bustPrice -= margin : bustPrice += margin;

    // Decrease the exposure based on the order's direction and size
    _increaseExposure(order.long, size);

    // Create a new Position struct
    Position memory pos = Position(
      price,
      bustPrice,
      order.col,
      uint32(block.timestamp),
      order.lev,
      order.player,
      order.long,
      false
    );

    // Store the position using the unique ID
    positions[id] = pos;

    // Emit an event to log the execution of the position
    emit PositionExecuted(id, pos);
  }

  function _calcPnl(
    uint96 size,
    uint64 openPrice,
    uint64 price,
    bool long
  ) internal pure returns (int96 pnl) {
    // Calculate the position's notional amount
    uint96 amount = (size * SCALE) / openPrice;
    // Calculate the price difference between the current price and the opening price
    int96 diff = int64(price) - int64(openPrice);

    // Calculate pnl based on the position's direction (long or short)
    if (long) {
      pnl = (int96(amount) * diff) / int96(SCALE);
    } else {
      pnl = (int96(amount) * -1 * diff) / int96(SCALE);
    }
  }

  /**
   * @notice internal view returns the amount of funding rate accured
   * @param openTime timestamp when the position was opened
   * @param size size of the position
   */
  function _calcFundingFee(uint32 openTime, uint96 size) internal view returns (uint96 fee) {
    // Get the current timestamp
    uint32 curTime = uint32(block.timestamp);

    // Retrieve the fund fee configuration from storage
    FundFeeConfig memory conf = fundFeeConfig;

    // Check if the current time is greater than or equal to the open time plus the buffer period
    if (curTime >= openTime + conf.buffer) {
      // Calculate the percentage of the fee based on the rate and time elapsed
      uint32 percent = conf.rate * ((curTime - openTime) / conf.period);

      // Ensure that the percentage does not exceed the maximum value (SCALE)
      if (percent > SCALE) {
        percent = uint32(SCALE);
      }

      // Calculate the funding fee based on the position size and the calculated percentage
      fee = (size * percent) / SCALE;
    }
  }

  function _calcProfitFee(uint96 priceMove, uint96 size) internal view returns (uint96) {
    // Check if the provided price move is within the specified range
    if (maxPriceMove > priceMove && priceMove >= minPriceMove) {
      // calculate the max fee
      uint96 diff = (maxFeeAtMaxPs - maxFeeAtMinPs) * SCALE;

      uint96 positionRange = (maxPositionSize - minPositionSize) * SCALE;
      // calculate the fee using linear interpolation
      uint96 maxFee = (diff * (size - minPositionSize)) / (positionRange) + maxFeeAtMinPs;
      // calculate the shift amount based on the position size
      // shift amount will be add to the result of the fee calculation to shift the fee curve
      int96 shift = (-500001 + (int96(size) * 500001)) / int96(10 ** 13);
      // Calculate the fee using linear interpolation

      return
        uint96(shift) +
        maxFee -
        ((maxFee - minFee) * (priceMove - minPriceMove)) /
        (maxPriceMove - minPriceMove);
    }

    // If the price move is out of the specified range, return the min fee
    // it means the price move is greater than the max price move, it should return the min fee
    return minFee;
  }

  /**
   * @notice Function to calculate the price move percentage.
   * @param openPrice The open price of the position.
   * @param closePrice The close price of the position.
   */
  function _calcPriceMovePerc(
    uint96 openPrice,
    uint96 closePrice
  ) internal pure returns (uint96 pm_) {
    int96 diff = int96(closePrice) - int96(openPrice);
    // if the diff is negative, make it positive
    diff < 0 ? diff = diff * -1 : diff;
    return (uint96(diff) * SCALE) / openPrice;
  }

  function _share(uint96 amount, address player) internal returns (uint96) {
    // Calculate the bribe amount based on the specified amount and bribe rate
    uint96 bribe = (amount * bribeRate) / SCALE;

    // Calculate the reward for the player and set it using the setRefReward function
    uint96 reward = setRefReward(player, bribe);

    // Update the pending bribe by subtracting the reward
    pendingBribe += bribe - reward;

    // Return the difference between the bribe and the reward as the shared amount
    return bribe - reward;
  }

  function calcProfit(
    uint96 col,
    uint96 size,
    uint64 openPrice,
    uint64 price,
    uint32 openTime,
    bool long
  ) public view returns (uint96, uint96, uint96) {
    // Calculate the profit for the position using the _calcPnl function
    int96 profit = _calcPnl(size, openPrice, price, long);
    // Ensure that the profit is greater than zero
    require(profit > 0, "not in profit");
    // Calculate the percentage price move using the _calcPriceMovePerc function
    uint96 pm = _calcPriceMovePerc(openPrice, price);

    // Calculate the profit fee based on the profit and percentage price move
    uint96 pf = (uint96(profit) * _calcProfitFee(pm, size)) / SCALE;

    // Calculate the funding fee based on the open time and position size
    uint96 ff = _calcFundingFee(openTime, size);

    // Calculate the excluded profit, limited by the maximum profit
    uint96 excluded = uint96(profit) - pf;

    // Limit the excluded profit by the maximum profit value
    if (excluded > maxProfit) {
      excluded = maxProfit;
    }

    // Calculate the payout and reduce it by the funding fee if it's greater than the payout
    uint96 payout = excluded + col;
    payout = ff > payout ? 0 : payout - ff;

    // Reduce the excluded profit by the funding fee if it's greater than the excluded profit
    excluded = ff > excluded ? 0 : excluded - ff;

    return (payout, excluded, pm);
  }

  function _liquidate(bytes32 id, Position memory pos, uint64 price) internal {
    // Ensure that the position is not already closed
    require(!pos.close, "Position is closed");

    // Calculate the liquidator fee based on the position's collateral and the liquidator fee rate
    uint96 liqFee = (pos.col * liquidatorFee) / SCALE;

    // Share a portion of the collateral with the position's player and calculate the remaining pay-in amount
    uint96 shared = _share(pos.col, pos.player);
    uint96 payin = pos.col - liqFee - shared;

    // Increment the liquidator's fees with the liquidation fee
    liquidatorFees[msg.sender] += liqFee;

    // Increase the budget with the pay-in amount
    budget += payin;

    // Transfer the pay-in amount to the vault
    vault.payin(address(asset), address(this), payin);

    // Emit an event to log the liquidation of the position
    emit PositionLiquidated(id, price, pos);
  }

  function _close(address player, address to, uint96 col, uint96 payout) internal {
    // Calculate the pay-in amount by subtracting the payout from the collateral
    uint96 payin = col - payout;

    // Share a portion of the pay-in amount with the player and calculate the remaining shared amount
    uint96 shared = _share(payin, player);

    // Increase the budget with the pay-in amount reduced by the shared amount
    budget += payin - shared;

    // Transfer the remaining shared amount and the payout to the specified recipient
    vault.payout(address(asset), address(this), col - shared, to, payout);
  }

  function _closeInLoss(
    bytes32 id,
    Position memory pos,
    uint64 price,
    uint96 size,
    bool isSwap
  ) internal onlyPosOwnerAndNotClosed(id, isSwap) {
    require(pos.openTime + minPositionDuration <= block.timestamp, "too early to close");
    // Calculate the loss by negating the profit calculated by _calcPnl
    uint96 loss = uint96(_calcPnl(size, pos.openPrice, price, pos.long) * -1);

    // Calculate the funding fee for the position
    uint96 fundFee = _calcFundingFee(pos.openTime, size);

    // Add the funding fee to the loss if it's greater than zero
    if (fundFee > 0) {
      loss += fundFee;
    }

    // Calculate the payout by subtracting the loss from the collateral
    uint96 payout = loss > pos.col ? 0 : pos.col - loss;

    // If the payout is zero, revert the transaction with a specific error
    if (payout == 0) {
      revert LiquidatedByFees();
    }

    // Close the position by paying out the player
    _close(pos.player, pos.player, pos.col, payout);

    // Emit an event to log the closure of the position
    emit PositionClosed(id, price, pos);
  }

  function _closeInProfit(
    bytes32 id,
    Position memory pos,
    uint64 price,
    uint96 size,
    bool isSwap
  ) internal onlyPosOwnerAndNotClosed(id, isSwap) returns (uint96) {
    require(pos.openTime + minPositionDuration <= block.timestamp, "too early to close");
    // Calculate the payout, profit, and percentage price move using calcProfit
    (uint96 payout, uint96 profit, ) = calcProfit(
      pos.col,
      size,
      pos.openPrice,
      price,
      pos.openTime,
      pos.long
    );

    // Check if the profit is greater than the budget and revert if true
    if (profit > budget) {
      revert Halted();
    }

    if (payout > 0 && profit == 0) {
      // Close the position by paying out the player
      _close(pos.player, msg.sender, pos.col, payout);
    } else if (payout == 0 && profit == 0) {
      // Revert the transaction with a specific error if both payout and profit are zero
      revert LiquidatedByFees();
    } else {
      // Deduct the profit from the budget and transfer the payout to the player
      budget -= profit;
      vault.payout(address(asset), address(this), pos.col, msg.sender, payout);
    }

    // Emit an event to log the closure of the position
    emit PositionClosed(id, price, pos);

    return payout;
  }

  function closePosition(bytes[] calldata priceData, bytes32 id) external {
    // Update the price using the provided price data
    uint64 price = updatePrice(priceData);

    // Retrieve the position from the positions mapping
    Position memory pos = positions[id];

    // Ensure that the position exists (player is not the zero address)
    require(pos.player != address(0), "Position not found");

    // Calculate the position size
    uint96 size = pos.col * pos.lev;

    if (pos.long) {
      if (price <= pos.bustPrice) {
        // Liquidate the position if the price is at or below the bust price
        _liquidate(id, pos, price);
      } else if (price <= pos.openPrice) {
        // Close the position in loss if the price is at or below the open price
        _closeInLoss(id, pos, price, size, false);
      } else {
        // Close the position in profit if none of the previous conditions are met
        _closeInProfit(id, pos, price, size, false);
      }
    } else {
      if (price >= pos.bustPrice) {
        // Liquidate the position if the price is at or above the bust price
        _liquidate(id, pos, price);
      } else if (price >= pos.openPrice) {
        // Close the position in loss if the price is at or above the open price
        _closeInLoss(id, pos, price, size, false);
      } else {
        // Close the position in profit if none of the previous conditions are met
        _closeInProfit(id, pos, price, size, false);
      }
    }

    // Mark the position as closed
    positions[id].close = true;

    // Increase the exposure based on the position's direction and size
    _decreaseExposure(pos.long, size);
  }

  function closePositionSwap(
    bytes[] calldata priceData,
    bytes32 id
  ) external onlyRole(OPERATOR) returns (uint96) {
    // Update the price using the provided price data
    uint64 price = updatePrice(priceData);

    // Retrieve the position from the positions mapping
    Position memory pos = positions[id];

    // Ensure that the position exists (player is not the zero address)
    require(pos.player != address(0), "Position not found");

    // Calculate the position size
    uint96 size = pos.col * pos.lev;

    uint96 payout;

    if (pos.long) {
      // Check if the position is not liquidable and is not in loss
      if (price > pos.openPrice) {
        // Close the position in profit and record the payout
        payout = _closeInProfit(id, pos, price, size, true);
      } else {
        // Revert with a specific error if the position cannot be closed
        revert CanNotCloseSwap();
      }
    } else {
      // Check if the position is not liquidable and is not in loss
      if (price < pos.openPrice) {
        // Close the position in profit and record the payout
        payout = _closeInProfit(id, pos, price, size, true);
      } else {
        // Revert with a specific error if the position cannot be closed
        revert CanNotCloseSwap();
      }
    }

    // Mark the position as closed
    positions[id].close = true;

    // Increase the exposure based on the position's direction and size
    _decreaseExposure(pos.long, size);

    return payout;
  }

  function liquidateByFee(bytes[] calldata priceData, bytes32 id) external {
    // Update the price using the provided price data
    uint64 price = updatePrice(priceData);

    // Retrieve the position from the positions mapping
    Position memory pos = positions[id];

    // Calculate the position size
    uint96 size = pos.col * pos.lev;

    // Initialize the payout as the full collateral amount
    uint96 payout = pos.col;

    // Check if the position is in a loss
    if ((pos.long && price <= pos.openPrice) || (!pos.long && price >= pos.openPrice)) {
      // Calculate the loss and funding fee
      uint96 loss = uint96(_calcPnl(size, pos.openPrice, price, pos.long) * -1);
      uint96 ff = _calcFundingFee(pos.openTime, size);

      // Deduct the loss from the payout, if the loss is not greater than the payout
      payout = loss > payout ? 0 : payout - loss;

      // Deduct the funding fee from the payout, if the funding fee is not greater than the payout
      payout = ff > payout ? 0 : payout - ff;
    } else {
      // Calculate the payout based on profit and other factors using the calcProfit function
      (payout, , ) = calcProfit(pos.col, size, pos.openPrice, price, pos.openTime, pos.long);
    }

    // If the payout is greater than zero, revert the transaction with a specific error
    if (payout > 0) {
      revert NotLiquidableByFees();
    }

    // Mark the position as closed
    positions[id].close = true;

    // Increase the total exposure based on the position's direction and size
    _decreaseExposure(pos.long, size);

    // Liquidate the position based on fee-related conditions
    _liquidate(id, pos, price);
  }

  function liquidateBySecondary(bytes32 id) external onlyRole(KEEPER) {
    // Check if the secondary price feed is enabled
    require(isSecondaryEnabled, "Secondary price feed is not enabled");

    // Get the price from the secondary price feed
    uint64 price = getPriceFromSecondary();

    // Retrieve the position from the positions mapping
    Position memory pos = positions[id];

    if (pos.long) {
      require(price <= pos.bustPrice, "Price is not below bust price");
    } else {
      require(price >= pos.bustPrice, "Price is not above bust price");
    }

    // Mark the position as closed
    positions[id].close = true;

    // Increase the total exposure based on the position's direction and size
    uint96 size = pos.col * pos.lev;
    _decreaseExposure(pos.long, size);

    // Liquidate the position using the secondary price and related functions
    _liquidate(id, pos, price);
  }

  function emergencyClose(
    bytes[] calldata priceUpdateData,
    bytes32 id
  ) external onlyPosOwnerAndNotClosed(id, false) {
    // Update the price using the provided price update data
    uint64 price = updatePrice(priceUpdateData);

    // Retrieve the position from the positions mapping
    Position memory pos = positions[id];

    // Calculate the position size
    uint96 size = pos.col * pos.lev;

    // Calculate profit using the calcProfit function
    (, uint96 profit_, ) = calcProfit(pos.col, size, pos.openPrice, price, pos.openTime, pos.long);

    // Check if the profit is less than the budget, and revert if true
    if (profit_ < budget) {
      revert NotHalted();
    }

    // Mark the position as closed
    positions[id].close = true;

    // Transfer the position's collateral back to the player
    asset.safeTransfer(address(pos.player), pos.col);

    // Increase the exposure based on the position's direction and size
    _decreaseExposure(pos.long, size);

    // Emit an event to log the emergency closure of the position
    emit PositionClosedEmergency(id, pos);
  }

  function claimLiquidatorFees() external {
    // Retrieve the amount of liquidator fees assigned to the sender
    uint96 amount = liquidatorFees[msg.sender];

    // Check if there are fees to claim, and revert if the amount is zero
    require(amount > 0, "No fees to claim");

    // Set the liquidator fees for the sender to zero
    liquidatorFees[msg.sender] = 0;

    // Transfer the claimed fees to the sender's address
    asset.safeTransfer(msg.sender, amount);

    // Emit an event to log the collection of liquidator fees
    emit LiquidatorFeesCollected(msg.sender, amount, false);
  }

  function claimLiquidatorFeesSwap(
    address liquidator
  ) external override onlyRole(OPERATOR) returns (uint96 amount_) {
    // Check if the provided liquidator address is allowed for swap
    require(swapAllowed[liquidator], "Swap not allowed");

    // Retrieve the amount of liquidator fees assigned to the liquidator address
    uint96 amount = liquidatorFees[liquidator];

    // Check if there are fees to claim, and revert if the amount is zero
    require(amount > 0, "No fees to claim");

    // Set the liquidator fees for the liquidator address to zero
    liquidatorFees[liquidator] = 0;

    // Transfer the claimed fees to the operator's address (msg.sender)
    asset.safeTransfer(msg.sender, amount);

    // Emit an event to log the collection of liquidator fees in a swap context
    emit LiquidatorFeesCollected(liquidator, amount, true);

    return amount;
  }

  function transferBribe() external {
    // Retrieve the amount of pending bribe
    uint96 amount = pendingBribe;

    // Check if there is a bribe to claim, and revert if the amount is zero
    require(amount > 0, "No bribe to claim");

    // Set the pending bribe to zero
    pendingBribe = 0;

    // Transfer the bribe to the vault's address
    asset.safeTransfer(address(vault), amount);

    // Pay in the wager fee to the vault
    vault.payinWagerFee(address(asset));

    // Emit an event to log the transfer of the bribe
    emit BribeTransferred(amount);
  }

  // function that allows to deposit eth to the contract
  receive() external payable {}

  // function that allows the admin to withdraw eth from the contract
  function withdrawEth(address payable _to, uint256 _amount) external onlyRole(CONTROLLER) {
    _to.transfer(_amount);
  }
}

