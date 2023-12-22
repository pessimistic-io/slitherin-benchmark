// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {ILevelOracle} from "./ILevelOracle.sol";
import {IPoolHook} from "./IPoolHook.sol";
import {ILiquidityCalculator} from "./ILiquidityCalculator.sol";
import {IInterestRateModel} from "./IInterestRateModel.sol";
import {DataTypes} from "./DataTypes.sol";
import {IFeeDiscount} from "./IFeeDiscount.sol";

abstract contract PoolStorage {
    address public feeDistributor;

    ILevelOracle public oracle;

    ILiquidityCalculator public liquidityCalculator;

    address public orderManager;

    address public controller;

    IPoolHook public poolHook;

    /// @notice charge when changing position size
    uint256 public positionFee;
    /// @notice charge when liquidate position (in dollar)
    uint256 public liquidationFee;

    /// @notice part of fee will be kept for DAO, the rest will be distributed to pool amount, thus
    /// increase the pool value and the price of LP token
    uint256 public daoFee;
    /// @notice interest accrued in using number of epoch
    uint256 public accrualInterval;

    // ========= Assets management =========
    mapping(address => bool) public isAsset;
    /// @notice A list of all configured assets
    /// Note that token will not be removed from this array when it was delisted. We keep this
    /// list to calculate pool value properly
    address[] public allAssets;
    /// @notice only listed asset can be deposite or used as collteral
    mapping(address token => bool) public isListed;

    mapping(address token => bool) public isStableCoin;
    /// @notice amount reserved for fee
    mapping(address token => uint256) public feeReserves;
    /// @notice recorded balance of token in pool
    mapping(address token => uint256) public poolBalances;
    /// @notice last borrow index update timestamp
    mapping(address token => uint256) public lastAccrualTimestamps;
    /// @notice accumulated interest rate
    mapping(address token => uint256) public borrowIndices;
    /// @notice target weight for each tokens
    mapping(address token => uint256) public targetWeights;
    /// @notice total target weight
    uint256 public totalWeight;

    mapping(address lpToken => bool) public isTranche;
    /// @notice risk factor of each token in each tranche
    mapping(address token => mapping(address tranche => uint256 factor)) public riskFactor;
    /// @dev token => total risk score
    mapping(address token => uint256 totalFactor) public totalRiskFactor;
    /// @notice list of all tranches
    address[] public allTranches;
    /// @dev tranche => token => asset info
    mapping(address tranche => mapping(address token => DataTypes.AssetInfo)) public trancheAssets;
    /// @notice position reserve in each tranche
    mapping(address tranche => mapping(bytes32 positionKey => uint256)) public tranchePositionReserves;
    /// @notice maximum liquidity pool can take
    mapping(address token => uint256 amount) public maxLiquidity;

    // ========= Positions management =========

    /// @notice max leverage for all market
    uint256 public maxLeverage;
    /// @notice positions tracks all open positions
    mapping(bytes32 positionKey => DataTypes.Position) public positions;
    /// @notice minimum collateral value investor must hold to keep their position
    uint256 public maintenanceMargin;
    /// @notice cached pool value for faster computation
    uint256 public virtualPoolValue;
    /// @notice total SHORT size of each market
    mapping(address indexToken => uint256) public maxGlobalShortSizes;
    /// @notice total LONG size of each market cannot large than this ratio
    mapping(address indexToken => uint256) public maxGlobalLongSizeRatios;
    /// @notice total SHORT size of all token on all tranches
    uint256 public globalShortSize;
    /// @notice increase each time position newly opnen
    mapping(bytes32 positionKey => uint256) public positionRevisions;

    mapping(address token => IInterestRateModel) public interestRateModel;

    mapping(address => bool) public allowSwap;

    mapping(bytes32 positionKey => uint256) public positionOpenTimestamp;

    IFeeDiscount public feeDiscount;
}

