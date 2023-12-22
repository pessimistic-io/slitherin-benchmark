pragma solidity >= 0.8.0;

import {IPool} from "./IPool.sol";
import {ILevelOracle} from "./ILevelOracle.sol";
import {ILiquidityCalculator} from "./ILiquidityCalculator.sol";
import {DataTypes} from "./DataTypes.sol";

interface IPoolWithStorage is IPool {
    function oracle() external view returns (ILevelOracle);
    function trancheAssets(address tranche, address token) external view returns (DataTypes.AssetInfo memory);
    function allTranches(uint256 index) external view returns (address);
    function positions(bytes32 positionKey) external view returns (DataTypes.Position memory);
    function isStableCoin(address token) external view returns (bool);
    function poolBalances(address token) external view returns (uint256);
    function feeReserves(address token) external view returns (uint256);
    function borrowIndices(address token) external view returns (uint256);
    function lastAccrualTimestamps(address token) external view returns (uint256);
    function daoFee() external view returns (uint256);
    function riskFactor(address token, address tranche) external view returns (uint256);
    function liquidityCalculator() external view returns (ILiquidityCalculator);
    function targetWeights(address token) external view returns (uint256);
    function totalWeight() external view returns (uint256);
    function virtualPoolValue() external view returns (uint256);
    function isTranche(address tranche) external view returns (bool);
    function positionFee() external view returns (uint256);
    function liquidationFee() external view returns (uint256);
}

