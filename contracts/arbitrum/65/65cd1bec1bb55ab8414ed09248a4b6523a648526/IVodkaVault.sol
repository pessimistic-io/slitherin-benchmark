// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IRewardsController } from "./IRewardsController.sol";
import { IPoolAddressesProvider } from "./IPoolAddressesProvider.sol";
import { IPool } from "./IPool.sol";
import { IPriceOracle } from "./IPriceOracle.sol";
import { ISwapRouter } from "./ISwapRouter.sol";

import { IERC4626 } from "./IERC4626.sol";
import { IBorrower } from "./IBorrower.sol";
import { IBalancerVault } from "./IBalancerVault.sol";

interface IVodkaVault is IERC4626, IBorrower {
    error InvalidWithdrawFeeBps();
    error InvalidSlippageThresholdSwapBtc();
    error InvalidSlippageThresholdSwapEth();
    error InvalidSlippageThresholdGmx();
    error InvalidRebalanceTimeThreshold();
    error InvalidRebalanceDeltaThresholdBps();
    error InvalidRebalanceHfThresholdBps();
    error InvalidTargetHealthFactor();

    error InvalidRebalance();
    error DepositCapExceeded();
    error OnlyKeeperAllowed(address msgSender, address authorisedKeeperAddress);

    error NotWaterVault();
    error NotBalancerVault();

    error ArraysLengthMismatch();
    error FlashloanNotInitiated();

    error InvalidFeeRecipient();
    error InvalidFeeBps();

    event Rebalanced();
    event AllowancesGranted();

    event WaterVaultUpdated(address _waterVault);
    event KeeperUpdated(address _newKeeper);
    event FeeParamsUpdated(uint256 feeBps, address _newFeeRecipient);
    event WithdrawFeeUpdated(uint256 _withdrawFeeBps);
    event FeesWithdrawn(uint256 feeAmount);

    event DepositCapUpdated(uint256 _newDepositCap);
    event BatchingManagerUpdated(address _batchingManager);

    event AdminParamsUpdated(
        address newKeeper,
        address waterVault,
        uint256 newDepositCap,
        address batchingManager,
        uint16 withdrawFeeBps
    );
    event ThresholdsUpdated(
        uint16 slippageThresholdSwapBtcBps,
        uint16 slippageThresholdSwapEthBps,
        uint16 slippageThresholdGmxBps,
        uint128 usdcConversionThreshold,
        uint128 wethConversionThreshold,
        uint128 hedgeUsdcAmountThreshold,
        uint128 partialBtcHedgeUsdcAmountThreshold,
        uint128 partialEthHedgeUsdcAmountThreshold
    );
    event RebalanceParamsUpdated(
        uint32 rebalanceTimeThreshold,
        uint16 rebalanceDeltaThresholdBps,
        uint16 rebalanceHfThresholdBps
    );

    event HedgeParamsUpdated(
        IBalancerVault vault,
        ISwapRouter swapRouter,
        uint256 targetHealthFactor,
        IRewardsController aaveRewardsController,
        IPool pool,
        IPriceOracle oracle
    );

    function harvestFees() external;

    function depositCap() external view returns (uint256);

    function getPriceX128() external view returns (uint256);

    function getVaultMarketValue() external view returns (int256);

    function getMarketValue(uint256 assetAmount) external view returns (uint256 marketValue);
}

