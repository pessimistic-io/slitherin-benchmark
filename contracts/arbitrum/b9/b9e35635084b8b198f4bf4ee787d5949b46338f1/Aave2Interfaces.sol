//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20Upgradeable.sol";
import "./DataTypes.sol";
import "./Aave2DataTypes.sol";

interface IAaveProtocolDataProvider {
  function ADDRESSES_PROVIDER() external view returns (address);
  function getAllReservesTokens() external view returns (AaveDataTypes.TokenData[] memory);
  function getAllATokens() external view returns (AaveDataTypes.TokenData[] memory);
  function getReserveConfigurationData(address asset) external view returns (
    uint256 decimals,
    uint256 ltv,
    uint256 liquidationThreshold,
    uint256 liquidationBonus,
    uint256 reserveFactor,
    bool usageAsCollateralEnabled,
    bool borrowingEnabled,
    bool stableBorrowRateEnabled,
    bool isActive,
    bool isFrozen
  );
  function getReserveData(address asset) external view returns (
    uint256 availableLiquidity,
    uint256 totalStableDebt,
    uint256 totalVariableDebt,
    uint256 liquidityRate,
    uint256 variableBorrowRate,
    uint256 stableBorrowRate,
    uint256 averageStableBorrowRate,
    uint256 liquidityIndex,
    uint256 variableBorrowIndex,
    uint40 lastUpdateTimestamp
  );
  function getUserReserveData(address asset, address user) external view returns (
    uint256 currentATokenBalance,
    uint256 currentStableDebt,
    uint256 currentVariableDebt,
    uint256 principalStableDebt,
    uint256 scaledVariableDebt,
    uint256 stableBorrowRate,
    uint256 liquidityRate,
    uint40 stableRateLastUpdated,
    bool usageAsCollateralEnabled
  );
  function getReserveTokensAddresses(address asset) external view returns (
    address aTokenAddress,
    address stableDebtTokenAddress,
    address variableDebtTokenAddress
  );
}

interface ILendingPoolAddressesProvider {
  function getLendingPool() external view returns (address);
  function getPriceOracle() external view returns (address);
}

interface ILendingPool {
  function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
  function withdraw(address asset, uint256 amount, address to) external returns (uint256);
  function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
  function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);
  function swapBorrowRateMode(address asset, uint256 rateMode) external;
  function rebalanceStableBorrowRate(address asset, address user) external;
  function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;
  function liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken) external;

  function getUserAccountData(address user) external view returns (
    uint256 totalCollateralETH,
    uint256 totalDebtETH,
    uint256 availableBorrowsETH,
    uint256 currentLiquidationThreshold,
    uint256 ltv,
    uint256 healthFactor
  );
  function getReserveData(address asset) external view returns (Aave2DataTypes.ReserveData memory);
  function getReservesList() external view returns (address[] memory);
}

interface V2_ICreditDelegationToken is IERC20Upgradeable {
    function approveDelegation(address delegatee, uint256 amount) external;
    function borrowAllowance(address fromUser, address toUser) external view returns (uint256);
}

interface V2_IAToken is IERC20Upgradeable {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    function POOL() external view returns (address);
    function getIncentivesController() external view returns (address);
    function name() external view returns(string memory);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    function _nonces(address owner) external view returns (uint256);
}

interface IAaveIncentivesController {
  function getAssetData(address asset) external view returns (uint256, uint256, uint256);
  function assets(address asset) external view returns (uint128, uint128, uint256);
  function getClaimer(address user) external view returns (address);
  function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);

  function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);
  function claimRewardsOnBehalf(address[] calldata assets, uint256 amount, address user, address to) external returns (uint256);

  function getUserUnclaimedRewards(address user) external view returns (uint256);
  function getUserAssetData(address user, address asset) external view returns (uint256);
  function REWARD_TOKEN() external view returns (address);
  function PRECISION() external view returns (uint8);
  function DISTRIBUTION_END() external view returns (uint256);
  function STAKE_TOKEN() external view returns (address);
}

interface IStakedTokenV2 {
  function STAKED_TOKEN() external view returns (address);
}

interface IAaveOracle {
    function getAssetPrice(address asset) external view returns (uint256);
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);
}
