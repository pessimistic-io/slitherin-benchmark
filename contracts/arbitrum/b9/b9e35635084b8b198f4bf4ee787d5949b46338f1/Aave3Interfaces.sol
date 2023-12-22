//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20Upgradeable.sol";
import "./DataTypes.sol";
import "./Aave3DataTypes.sol";

interface IPoolAddressesProvider {
  function getPool() external view returns (address);
  function getPriceOracle() external view returns (address);
  function getPoolDataProvider() external view returns (address);
}

interface IPoolDataProvider {
    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider);
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
    function getReserveEModeCategory(address asset) external view returns (uint256);
    function getReserveCaps(address asset) external view returns (uint256 borrowCap, uint256 supplyCap);
    function getPaused(address asset) external view returns (bool isPaused);
    function getSiloedBorrowing(address asset) external view returns (bool);
    function getLiquidationProtocolFee(address asset) external view returns (uint256);
    function getUnbackedMintCap(address asset) external view returns (uint256);
    function getDebtCeiling(address asset) external view returns (uint256);
    function getDebtCeilingDecimals() external pure returns (uint256);
    function getReserveData(address asset) external view returns (
        uint256 unbacked,
        uint256 accruedToTreasuryScaled,
        uint256 totalAToken,
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
    function getATokenTotalSupply(address asset) external view returns (uint256);
    function getTotalDebt(address asset) external view returns (uint256);
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
    function getInterestRateStrategyAddress(address asset) external view returns (address irStrategyAddress);
    function getFlashLoanEnabled(address asset) external view returns (bool);
}

interface IPool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function supplyWithPermit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode, uint256 deadline, uint8 permitV, bytes32 permitR, bytes32 permitS) external;
    function withdraw(address asset, uint256 amount, address to ) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf) external returns (uint256);
    function repayWithPermit(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf, uint256 deadline, uint8 permitV, bytes32 permitR, bytes32 permitS) external returns (uint256);
    function repayWithATokens(address asset, uint256 amount, uint256 interestRateMode) external returns (uint256);
    function swapBorrowRateMode(address asset, uint256 interestRateMode) external;
    function rebalanceStableBorrowRate(address asset, address user) external;
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;
    function liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken) external;

    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
    function getReserveData(address asset) external view returns (Aave3DataTypes.ReserveData memory);
    function getReservesList() external view returns (address[] memory);
}

interface V3_ICreditDelegationToken is IERC20Upgradeable {
    function approveDelegation(address delegatee, uint256 amount) external;
    function borrowAllowance(address fromUser, address toUser) external view returns (uint256);

    function delegationWithSig(
        address delegator,
        address delegatee,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function name() external view returns(string memory);
    function nonces(address owner) external view returns (uint256);
}

interface V3_IAToken is IERC20Upgradeable {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    function POOL() external view returns (address);
    function getIncentivesController() external view returns (address);
    function name() external view returns(string memory);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    function nonces(address owner) external view returns (uint256);
}

interface IRewardsController {
    /// @dev asset The incentivized asset. It should be address of AToken or VariableDebtToken
    function getRewardsByAsset(address asset) external view returns (address[] memory);
    function getRewardsData(address asset, address reward) external view returns (
      uint256 index,
      uint256 emissionPerSecond,
      uint256 lastUpdateTimestamp,
      uint256 distributionEnd
    );
    function getAllUserRewards(address[] calldata assets, address user) external view returns (address[] memory, uint256[] memory);
    function getUserRewards(address[] calldata assets, address user, address reward) external view returns (uint256);
    function claimAllRewards(address[] calldata assets, address to) external returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
    function claimAllRewardsToSelf(address[] calldata assets) external returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}

