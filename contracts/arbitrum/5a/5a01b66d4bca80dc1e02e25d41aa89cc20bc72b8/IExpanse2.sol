// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IExpanse2 {
  /// @dev Emitted when position created successfully
  event PositionCreated(address indexed clientUUID);

  /// @dev Emitted when position changed successfully
  event PositionChanged(address indexed clientUUID);

  /// @dev Emitted when successfully swap from USDCE to WBTC
  event SwappedToWBTC(address[] clientUUIDs);

  /// @dev Emitted when successfully swap from WBTC to USDCE
  event SwappedToUSDCE(address[] clientUUIDs);

  /// @dev Emitted when successfully supply WBTC tokens to AAVE pool and set it as collateral
  event Collateralized(address[] clientUUIDs);

  /// @dev Emitted when successfully withdraw WBTC tokens from AAVE pool for provided clients
  event LiquidityWithdrew(address[] clientUUIDs);

  /// @dev Emitted when successfully borrow USDCE tokens from AAVE pool for provided clients
  event Borrowed(address[] clientUUIDs);

  /// @dev Emitted when successfully repay USDCE tokens to AAVE pool for provided clients
  event Repaid(address[] clientUUIDs);

  enum State {
    Purchased,
    Collateralized,
    Levered,
    Closed
  }

  struct PositionInfo {
    State state;
    uint256 WBTC;
    uint256 USDCE;
    uint256 collateral;
    uint256 debt;
    uint256 entryAmount;
    uint256 entryPrice;
    uint256 averagePrice;
  }

  /// @notice Change leverage ratio
  /// @param _newLeverage The new leverage ratio
  function changeLeverage(uint256 _newLeverage) external;

  /// @notice Get leverage ratio
  /// @return leverage The current leverage ratio
  function getLeverage() external returns (uint256 leverage);

  /// @notice Change interest Rate Mode for AAVE
  /// @param _newInterestRateMode The new interest Rate Mode
  function changeInterestRateMode(uint256 _newInterestRateMode) external;

  /// @notice Get interest Rate Mode
  /// @return interestRateMode The current interest Rate Mode
  function getInterestRateMode() external returns (uint256 interestRateMode);

  /// @notice Create new client position
  /// @param clientUUID The identifier of client
  /// @param wbtcAmount The amount of WBTC in position
  /// @param usdceAmount The amount of USDCE in position
  function newPosition(address clientUUID, uint256 wbtcAmount, uint256 usdceAmount) external;

  /// @notice Change client position
  /// @param clientUUID The identifier of client
  /// @param state The state of position
  /// @param wbtcAmount The amount of WBTC in position
  /// @param usdceAmount The amount of USDCE in position
  /// @param wbtcEntryPrice The entry price of WBTC token
  function changePosition(
    address clientUUID,
    State state,
    uint256 wbtcAmount,
    uint256 usdceAmount,
    uint256 wbtcEntryPrice
  ) external;

  /// @notice Get current price of WBTC on Uniswap
  /// @return price in USDCE without decimals
  function calculateWBTCPrice() external view returns (uint256 price);

  /// @notice Get all recently closed client positions
  /// @param clientUUID The identifier of client
  /// @return Array of closed client positions
  function getPositionsHistory(address clientUUID) external view returns (PositionInfo[] memory);

  /// @notice Get all client positions
  /// @param clientUUID The identifier of client
  /// @return Info about selected client position
  function getPosition(address clientUUID) external view returns (PositionInfo memory);

  /// @notice Function that swaps USDCE tokens to exact amount of WBTC
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts of token
  function swapUSDCEtoWBTC(address[] memory clientUUIDs, uint256[] memory amounts) external;

  /// @notice Function that swaps WBTC tokens to exact amount of USDCE
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts of token
  function swapWBTCtoUSDCE(address[] memory clientUUIDs, uint256[] memory amounts) external;

  /// @notice Function that supply WBTC tokens to AAVE pool and set it as collateral
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts of token
  function supplyWBTCLiquidity(address[] memory clientUUIDs, uint256[] memory amounts) external;

  /// @notice Function that withdraw WBTC tokens from AAVE pool for provided clients
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts
  function withdrawWBTCLiquidity(address[] memory clientUUIDs, uint256[] memory amounts) external;

  /// @notice Function that borrow USDCE tokens from AAVE pool for provided clients
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts
  function borrowUSDCE(address[] memory clientUUIDs, uint256[] memory amounts) external;

  /// @notice Function that repay USDCE tokens to AAVE pool for provided clients
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts
  function repayUSDCE(address[] memory clientUUIDs, uint256[] memory amounts) external;

  /// @notice Get AAVE account data for entire contract collateral/borrow rates
  function getAAVEInfo()
    external
    returns (
      uint256 totalCollateralBase,
      uint256 totalDebtBase,
      uint256 availableBorrowsBase,
      uint256 liquidationThreshold,
      uint256 currentLtv,
      uint256 healthFactor,
      uint256 totalContractCollateral
    );

  /// @notice Withdraw ETH from the contract to the owner address
  /// @param amount The amount to withdraw
  function withdrawETH(uint256 amount) external;

  /// @notice Withdraw tokens from the contract to owner
  /// @param token The token to withdraw
  /// @param amount The amount to withdraw
  function withdraw(address token, uint256 amount) external;
}

