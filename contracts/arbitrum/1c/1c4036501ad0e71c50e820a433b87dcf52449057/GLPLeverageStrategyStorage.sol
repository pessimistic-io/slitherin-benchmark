// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./extensions_IERC20MetadataUpgradeable.sol";
import "./AggregatorV3Interface.sol";
import "./IRewardRouterV2.sol";
import "./IWrappedGLP.sol";
import "./ILendingPool.sol";
import "./ISwapRouter.sol";

contract GLPLeverageStrategyStorage {
    event MintGLPError(string message);

    uint256 internal constant BASIS_POINT = 1e4;

    enum Contracts {
        SwapRouter,
        GLPRewardRouterV2,
        LendingPool,
        ETHUSDOracle,
        Vault,
        Keeper
    }

    IRewardRouterV2 public glpRewardRouterV2;
    ILendingPool public lendingPool;
    ISwapRouter public swapRouter;
    AggregatorV3Interface public ethUSDOracle;
    uint256 public ethUSDOracleRefreshRate; // Chainlink default refresh rate for ETH/USD

    uint256 public minimumCollateralRatio;
    uint256 public targetCollateralRatio;

    IERC20MetadataUpgradeable public weth;
    IERC20MetadataUpgradeable public sGLP;
    IWrappedGLP public wrappedGLP;

    uint256 internal glpEquity;
    uint16 public lendingPoolRewardShare;

    address public vault;
    address public keeper;

    uint256 internal lastRewardClaimTime;
}

