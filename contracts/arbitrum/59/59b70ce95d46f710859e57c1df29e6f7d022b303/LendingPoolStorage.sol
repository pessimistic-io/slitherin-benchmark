// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./extensions_IERC20MetadataUpgradeable.sol";
import "./AggregatorV3Interface.sol";
import "./IRewardRouterV2.sol";
import "./IRewardReader.sol";
import "./IStrategy.sol";

contract LendingPoolStorage {
    struct BorrowState {
        uint256 principal;
        uint256 lastAccumulatedInterestRate;
    }

    enum Contracts {
        PriceFeedAgregatorV3
    }

    uint256 internal constant FACTOR = 1e18;

    uint256 internal assetScale;

    // Intrest rate piecewise parameters
    uint256 public interestRateBase;
    uint256 public interestRateSlope1;
    uint256 public interestRateSlope2;
    uint256 public interestRateUtilizationBound;
    uint256 internal collateralScale;

    IStrategy public strategy;

    // Chainlink interface for price feed: USDC/USD
    AggregatorV3Interface public lendingAssetPriceFeed;

    // Chainlink default refresh rate for USDC/USD
    uint256 public lendingAssetRefreshRate;

    // Address of collateral asset. i.e.: sGLP
    IERC20MetadataUpgradeable public collateralAsset;

    uint256 internal collateralFactor;

    // Total amount borrowed of base asset
    uint256 public totalBorrowed;

    // Total rate of interest earned by lending pool
    uint256 public totalAccumulatedInterestRate;

    // Amount of collateral provided by user
    mapping(address => uint256) public userCollateralAmount;

    // Amount of base asset borrowed by user
    mapping(address => BorrowState) public userBorrowState;

    uint256 public lastAccrueTime;
}

