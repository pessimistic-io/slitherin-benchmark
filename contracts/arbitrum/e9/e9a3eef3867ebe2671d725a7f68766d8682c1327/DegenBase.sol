// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IDegenBase.sol";
import "./IDegenPoolManager.sol";
import "./DegenStructs.sol";

/**
 * @title DegenBase
 * @author balding-ghost
 * @notice The base contract for the Degen game containing all the configuration and internal functions that are used by the DegenMain contract.
 */
contract DegenBase is IDegenBase {
  uint256 public constant VAULT_SCALING_INCREASE_FOR_USD = 1e12;
  uint256 internal constant PRICE_PRECISION = 1e18;
  uint256 public constant BASIS_POINTS = 1e6;

  // immutable configurations
  // pyth id of the targetMarketToken
  bytes32 public immutable pythAssetId;

  // address of the target market token, so the token that is used to open positions against, echt contract only tracks one asset
  address public immutable targetMarketToken;

  // address of usdc/stablecooin
  address public immutable stableTokenAddress;

  // decimals of the stable token
  uint256 public immutable stableTokenDecimals;

  // pool manager contract, handles position closing and payouts/payins
  IDegenPoolManager public immutable poolManager;

  uint256 public immutable decimalsToken;

  address public router;

  // max percentage of the vault the player is allowed to win (scaled by 1e6)
  uint256 public maxPercentageOfVault;

  // liquidation threshold is the threshold at which a position can be liquidated (margin level of the position), if this value is 90 * 1e4 (so 90%) the position can be liquidated when the margin level is below 90%. So with $100 margin, liquidation will start with a pnl of -$90
  uint256 public liquidationThreshold;

  // maximum allowed leverage, this is unscaled so 100x = 100
  uint256 public maxLeverage;

  // minimum allowed leverage, this is unscaled so 100x = 100
  uint256 public minLeverage;

  // funding rate buffer, this is the amount of seconds a position doesn't have to pay funding rate after it is opened
  uint256 public fundingRateTimeBuffer;

  // amount of seconds a position at the minimum needs to be open before it can be closed by a user
  uint256 public minimumPositionDuration;

  // max position size in usd (so the total amount of usd that can be used for a position) this is leverage * margin amount
  uint256 public constant maxPositionSizeUsd = 1e6 * 1e18; // 1m usd

  // min amount of margin in usd that the user needs to have to open a position
  uint256 public constant minMarginAmountUsd = 1e18; // 1 usd

  // percentage that is added to the funding rate (so the bottom/minium) regardless how skewed the open interest is this percentage will be added
  uint256 public minimumFundingRate;

  uint256 public maxFundingRate;

  // configurable value that determines how much the funding rate is affected by the open interest
  uint256 public fundingRateFactor;

  // max exposure for the asset, this is the total amount of long and short positions that can be open at the same time
  uint256 public maxExposureForAsset;

  uint256 public fundingFeePeriod = 60; // 1 minute defualt

  // if opening/executing new positions is allowed
  bool public openPositionAllowed;

  // if opening new orders is allowed
  bool public openOrderAllowed;

  // if closing positions is allowed
  bool public closePositionAllowed;

  // total amount of long positions open (so total long exposure)
  uint256 public totalLongExposureInTargetAsset;

  // total amount of short positions open (so total short exposure)
  uint256 public totalShortExposureInTargetAsset;

  constructor(
    address _targetToken,
    uint256 _decimals,
    address _poolManager,
    bytes32 _pythAssetId,
    address _stableToken,
    uint256 _stableDecimals
  ) {
    poolManager = IDegenPoolManager(_poolManager);
    decimalsToken = _decimals;
    stableTokenAddress = _stableToken;
    stableTokenDecimals = _stableDecimals;
    pythAssetId = _pythAssetId;
    targetMarketToken = _targetToken;
  }

  modifier onlyPoolManagerController() {
    require(poolManager.isDegenGameController(msg.sender), "Degen: not controller");
    _;
  }

  modifier onlyRouter() {
    require(msg.sender == router, "Degen: not router");
    _;
  }

  // configuration functions

  function setRouterAddress(address _routerAddress) external onlyPoolManagerController {
    router = _routerAddress;
    emit SetRouterAddress(_routerAddress);
  }

  function setFundingFeePeriod(uint256 _fundingFeePeriod) external onlyPoolManagerController {
    require(_fundingFeePeriod > 0, "Degen: funding fee period too low");
    fundingFeePeriod = _fundingFeePeriod;
    emit SetFundingFeePeriod(_fundingFeePeriod);
  }

  /**
   * @notice set the max percentage of the vault the player is allowed to win (scaled by 1e6)
   * @param _maxPercentageOfVault the max percentage of the vault the player is allowed to win (scaled by 1e6)
   */
  function setMaxPercentageOfVaultReserves(
    uint256 _maxPercentageOfVault
  ) external onlyPoolManagerController {
    maxPercentageOfVault = _maxPercentageOfVault;
    emit SetMaxPercentageOfVault(_maxPercentageOfVault);
  }

  /**
   * @notice set the minimum amount of time a position needs to be open before it can be closed
   * @param _minimumPositionDuration amount of seconds a position at the minimum needs to be open before it can be closed by a user
   */
  function setMinimumPositionDuration(
    uint256 _minimumPositionDuration
  ) external onlyPoolManagerController {
    minimumPositionDuration = _minimumPositionDuration;
    emit SetMinimumPositionDuration(_minimumPositionDuration);
  }

  /**
   * @notice set the funding rate time buffer, the amount of seconds a position doesn't have to pay funding rate after it is opened
   * @param _fundingRateTimeBuffer the new funding rate time buffer
   */
  function setFundingRateTimeBuffer(
    uint256 _fundingRateTimeBuffer
  ) external onlyPoolManagerController {
    fundingRateTimeBuffer = _fundingRateTimeBuffer;
    emit SetFundingRateTimeBuffer(_fundingRateTimeBuffer);
  }

  /**
   * @notice set the max leverage
   * @dev no scaling is needed, max 2x leverage is 2 etc
   * @param _maxLeverage the new max leverage
   */
  function setMaxLeverage(uint256 _maxLeverage) external onlyPoolManagerController {
    maxLeverage = _maxLeverage;
    emit SetMaxLeverage(_maxLeverage);
  }

  /**
   * @notice set the minimum leverage
   * @dev no scaling is needed, min 2x leverage is 2 etc
   * @param _minLeverage the new minimum leverage
   */
  function setMinLeverage(uint256 _minLeverage) external onlyPoolManagerController {
    minLeverage = _minLeverage;
    emit SetMinLeverage(_minLeverage);
  }

  /**
   * @notice set the liquidation threshold, scaled 1e6
   * @param _liquidationThreshold the new liquidation threshold, scaled 1e6
   */
  function setLiquidationThreshold(uint256 _liquidationThreshold) external {
    require(msg.sender == address(poolManager), "Degen: only pool manager");
    liquidationThreshold = _liquidationThreshold;
    emit SetLiquidationThreshold(_liquidationThreshold);
  }

  /**
   * @notice set whether opening positions is allowed
   * @param _openPositionAllowed boolean value indicating whether opening positions is allowed
   */
  function setOpenPositionAllowed(bool _openPositionAllowed) external onlyPoolManagerController {
    openPositionAllowed = _openPositionAllowed;
    emit SetOpenPositionAllowed(_openPositionAllowed);
  }

  /**
   * @notice set whether opening orders is allowed
   * @param _openOrderAllowed boolean value indicating whether opening orders is allowed
   */
  function setOpenOrderAllowed(bool _openOrderAllowed) external onlyPoolManagerController {
    openOrderAllowed = _openOrderAllowed;
    emit SetOpenOrderAllowed(_openOrderAllowed);
  }

  /**
   * @notice set whether closing positions is allowed
   * @param _closePositionAllowed boolean value indicating whether closing positions is allowed
   */
  function setClosePositionAllowed(bool _closePositionAllowed) external onlyPoolManagerController {
    closePositionAllowed = _closePositionAllowed;
    emit SetClosePositionAllowed(_closePositionAllowed);
  }

  /**
   * @notice set the funding rate factor
   * @param _fundingRateFactor the new funding rate factor
   */
  function setFundingRateFactor(uint256 _fundingRateFactor) external onlyPoolManagerController {
    fundingRateFactor = _fundingRateFactor;
    emit SetFundingRateFactor(_fundingRateFactor);
  }

  /**
   * @notice set the minimum funding rate
   * @param _minimumFundingRate the new minimum funding rate, scaled 1e6
   */
  function setMinimumFundingRate(uint256 _minimumFundingRate) external onlyPoolManagerController {
    require(_minimumFundingRate <= BASIS_POINTS, "Degen: funding rate too high");
    minimumFundingRate = _minimumFundingRate;
    emit SetMinimumFundingRate(_minimumFundingRate);
  }
  /**
   * @notice set the max funding rate
   * @param _maxFundingRate the new max funding rate, scaled 1e6
   */
  function setMaxFundingRate(uint256 _maxFundingRate) external onlyPoolManagerController {
    require(_maxFundingRate <= BASIS_POINTS, "Degen: max funding rate too high");
    maxFundingRate = _maxFundingRate;
    emit SetMaxFundingRate(_maxFundingRate);
  }
  /**
   * @notice set the max exposure for the asset
   * @param _maxExposureForAsset the new max exposure for the asset
   */
  function setMaxExposureForAsset(uint256 _maxExposureForAsset) external onlyPoolManagerController {
    maxExposureForAsset = _maxExposureForAsset;
    emit SetMaxExposureForAsset(_maxExposureForAsset);
  }

  function getFundingRate(bool _isLong) external view returns (uint256 _fundingRate) {
    _fundingRate = _updateFundingRate(_isLong);
  }

  // internal functions

  function _checkOpenOrderAllowed() internal view {
    require(openOrderAllowed, "Degen: open order not allowed");
  }

  function _checkOpenPositionAllowed() internal view {
    require(openPositionAllowed, "Degen: open position not allowed");
  }

  function _checkClosePositionAllowed() internal view {
    require(closePositionAllowed, "Degen: close position not allowed");
  }

  /**
   * @notice check if the position size is allowed
   * @param _leverage  amount of leverage to use for the position
   * @param _marginAmountAsset the wager amount held in the router in the asset of the contract
   * @param _currentPriceAsset the current price of the asset scaled 1e18
   */
  function _checkPositionSizeAsset(
    uint16 _leverage,
    uint256 _marginAmountAsset,
    uint256 _currentPriceAsset
  ) internal view returns (uint256 positionSizeUsd_, uint256 valueMarginUsd_) {
    unchecked {
      valueMarginUsd_ = (_marginAmountAsset * _currentPriceAsset) / (10 ** decimalsToken);
      positionSizeUsd_ = (valueMarginUsd_ * _leverage);
      require(positionSizeUsd_ <= maxPositionSizeUsd, "Degen: position size too high asset");
      require(valueMarginUsd_ >= minMarginAmountUsd, "Degen: position size too low asset");
    }
    return (positionSizeUsd_, valueMarginUsd_);
  }

  /**
   * @notice check if the position size is within bounds
   * @param _leverage  amount of leverage to use for the position
   * @param _wagerAmountUsdc the wager amount in USDC held in the router
   */
  function _checkPositionSizeWagerInUsdc(
    uint16 _leverage,
    uint256 _wagerAmountUsdc
  ) internal pure returns (uint256 positionSizeUsd_, uint256 marginValueUsd_) {

    unchecked {
      // convert the usdc wager (1e6) to usd value scaled 1e18
      marginValueUsd_ = _wagerAmountUsdc * VAULT_SCALING_INCREASE_FOR_USD;
      positionSizeUsd_ = (marginValueUsd_ * _leverage);
      require((positionSizeUsd_) <= maxPositionSizeUsd, "Degen: position size too high usd");
      require((marginValueUsd_) >= minMarginAmountUsd, "Degen: position size too low usd");
    }
    return (positionSizeUsd_, marginValueUsd_);
  }

  /**
   * @notice internal function that calculates the max position profit in the usd for a new position
   */
  function _maxPositionProfitUsd() internal view returns (uint256 _maxPositionProfitInAsset) {
    unchecked {
      _maxPositionProfitInAsset =
        (poolManager.returnVaultReserveInAsset() * maxPercentageOfVault) /
        BASIS_POINTS;
    }
  }

  /**
   * @notice interal function that checks if the position size is allowed
   * @param _positionOpenTimestamp the timestamp the position is being opened in
   * @return isAllowed_ boolean indicating if closing any position is allowed
   */
  function _isUserPositionCloseAllowed(
    uint256 _positionOpenTimestamp
  ) internal view returns (bool isAllowed_) {
    // check if the position is open long enough
    unchecked {
      isAllowed_ = block.timestamp >= (_positionOpenTimestamp + minimumPositionDuration);
    }
  }

  /**
   * @notice internal function that increases the open interest (for when a new position is opened)
   * @param _isLong if the new position is long
   * @param _positionSizeInTargetAsset the position size in target asset(ETH)
   */
  function _increaseOpenInterest(bool _isLong, uint256 _positionSizeInTargetAsset) internal {
    unchecked {
      if (_isLong) {
        // increase the total long exposure
        totalLongExposureInTargetAsset += _positionSizeInTargetAsset;
        require(totalLongExposureInTargetAsset <= maxExposureForAsset, "Degen: max exposure reached");
      } else {
        // increase the total short exposure
        totalShortExposureInTargetAsset += _positionSizeInTargetAsset;
        require(totalShortExposureInTargetAsset <= maxExposureForAsset, "Degen: max exposure reached");
      }
    }
  }

  /**
   * @notice internal function that decreases the open interest (for when a position is closed)
   * @param _isLong if the  position that is being closed is long or short
   * @param _positionSizeInTargetAsset the position size in target asset that is being closed
   */
  function _decreaseOpenInterest(bool _isLong, uint256 _positionSizeInTargetAsset) internal {
    unchecked {
      if (_isLong) {
        // decrease the total long exposure
        totalLongExposureInTargetAsset -= _positionSizeInTargetAsset;
      } else {
        // decrease the total short exposure
        totalShortExposureInTargetAsset -= _positionSizeInTargetAsset;
      }
    }
  }

  /**
   * open interest storage and configuration
   * The funding rate is the rate that is paid by the longs to the shorts (or vice versa) every second. The funding rate is calculated based on the open interest of the contract. If the open interest is skewed to the longs, the funding rate will be lower for the long and higher for the shorts.
   * Unlike other perpetual contracts, the Degen contract does not have funding rates that can go negative. Meaning that the funding rate is always positive.
   */
  function _updateFundingRate(bool _isLong) internal view returns (uint256 _fundingRate) {
    // calculate the skweness, if the skewness is positive the contract is long, if the skewness is negative the shorts is short
    int256 totalShort_ = int256(totalShortExposureInTargetAsset);
    int256 totalLong_ = int256(totalLongExposureInTargetAsset);
    int256 skewness_;
    unchecked {
      skewness_ = ((totalLong_ - totalShort_) * 1e6) / (totalLong_ + totalShort_);
    }

    if (_isLong) {
      // the user is opening a long position
      if (skewness_ < 0) {
        // skweness is negative, so the contract is short, this means that the funding rate is the minimum because the new position helps to balance the short exposure
        _fundingRate = minimumFundingRate;
      } else {
        // skewness is positive, so the contract is long, this means that the funding rate is the minimum plus the skewness with a factor, since the position is making the contract more long
        unchecked {
          _fundingRate =
            minimumFundingRate +
            ((uint256(skewness_) * fundingRateFactor) / BASIS_POINTS);
        }
      }
    } else {
      // the user is opening a short position
      if (skewness_ > 0) {
        // skweness is positive, so the contract is long, this means that the funding rate is the minimum because the new position helps to balance the long exposure
        _fundingRate = minimumFundingRate;
      } else {
        // skewness is negative, so the contract is short, this means that the funding rate is the minimum plus the skewness with a factor, since the position is making the contract more short
        unchecked {
          _fundingRate =
            minimumFundingRate +
            ((uint256(-skewness_) * fundingRateFactor) / BASIS_POINTS);
        }
      }
    }

    if(_fundingRate > maxFundingRate) {
      _fundingRate = maxFundingRate;
    }
  }
}

