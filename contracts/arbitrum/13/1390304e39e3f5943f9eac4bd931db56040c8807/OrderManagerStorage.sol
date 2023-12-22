pragma solidity 0.8.18;

import {DataTypes} from "./DataTypes.sol";
import {ILevelOracle} from "./ILevelOracle.sol";
import {IPool} from "./IPool.sol";
import {IOrderHook} from "./IOrderHook.sol";
import {IWETH} from "./IWETH.sol";
import {IETHUnwrapper} from "./IETHUnwrapper.sol";

abstract contract OrderManagerStorage {
    IWETH public weth;

    IPool public pool;
    ILevelOracle public oracle;
    IOrderHook public orderHook;
    address public executor;

    uint256 public nextLeverageOrderId;
    uint256 public nextSwapOrderId;
    uint256 public minLeverageExecutionFee;
    uint256 public minSwapExecutionFee;

    mapping(uint256 orderId => DataTypes.LeverageOrder) public leverageOrders;
    mapping(uint256 orderId => DataTypes.UpdatePositionRequest) public updatePositionRequests;
    mapping(uint256 orderId => DataTypes.SwapOrder) public swapOrders;
    mapping(address user => uint256[]) public userLeverageOrders;
    mapping(address user => uint256) public userLeverageOrderCount;
    mapping(address user => uint256[]) public userSwapOrders;
    mapping(address user => uint256) public userSwapOrderCount;

    uint256[] public marketLeverageOrders;
    uint256 public startMarketLeverageOrderIndex;
}

