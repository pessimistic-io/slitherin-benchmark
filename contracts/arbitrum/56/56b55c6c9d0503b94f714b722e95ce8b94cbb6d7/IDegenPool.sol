// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IDegenPool {
  // Structs
  struct Order {
    uint64 minPrice;
    uint64 maxPrice;
    uint48 col;
    uint32 validUntil;
    uint16 lev;
    bool long;
    address player;
  }

  struct Position {
    uint64 openPrice;
    uint64 bustPrice;
    uint48 col;
    uint32 openTime;
    uint16 lev;
    address player;
    bool long;
    bool close;
  }

  struct FundFeeConfig {
    uint16 rate;
    uint16 buffer;
    uint16 period;
  }

  // Errors
  error PriceOutRange();
  error MaxExposureReached(bool long);
  error Halted();
  error NotHalted();
  error LiquidatedByFees();
  error NotLiquidableByFees();
  error CanNotCloseSwap();

  // Events
  event PositionExecuted(bytes32 indexed sig, Position position);

  event PositionLiquidated(bytes32 indexed sig, uint64 price, Position position);

  event PositionClosed(bytes32 indexed sig, uint64 price, Position position);

  event PositionClosedEmergency(bytes32 indexed sig, Position position);

  event LiquidatorFeesCollected(address indexed liquidator, uint96 amount, bool swap);

  // event SetExpoConfig(uint96 maxExpo);

  // event UpdateBudget(uint96 budget);

  // event UpdateMaxProfit(uint96 maxProfit);
  event UpdateLimits(uint96 newBudget, uint96 newMaxProfit, uint96 maxExpo);

  event UpdateBribeRate(uint96 bribeRate);

  event UpdateFreshness(uint8 freshness);

  event UpdateLiquidatorFee(uint96 liquidatorFee);

  event UpdateFundFeeConfig(FundFeeConfig fundFeeConfig);

  // event UpdateMinPosDuration(uint32 minPosDuration);

  // event UpdateMinMaxLeverage(uint16 minLeverage, uint16 maxLeverage);
  event UpdatePosConf(
    uint16 newMinLeverage,
    uint16 newMaxLeverage,
    uint16 newMinPositionDuration,
    uint96 newMinWager
  );

  event SwapAllowed(address user, bool allowed);

  event SetSecondaryPriceFeed(address secondaryPriceFeed);

  event BribeTransferred(uint96 amount);

  event SecondaryEnabled(bool enabled, uint64 pairIndex);

  // event UpdateMinWager(uint96 minWager);

  event UpdatePythUpdateFee(uint32 newPythUpdateFee);

  // Functions
  function claimLiquidatorFeesSwap(address liquidator) external returns (uint96 amount_);

  function closePositionSwap(bytes[] calldata priceData, bytes32 id) external returns (uint96);

  function getPosition(bytes32 id) external view returns (Position memory);
}

