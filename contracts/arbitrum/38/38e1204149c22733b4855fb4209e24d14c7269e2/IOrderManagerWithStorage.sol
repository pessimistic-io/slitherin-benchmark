pragma solidity 0.8.18;

import "./IOrderManager.sol";
import {DataTypes} from "./DataTypes.sol";

interface IOrderManagerWithStorage is IOrderManager {
    function leverageOrders(uint256 id) external view returns (DataTypes.LeverageOrder memory);
    function updatePositionRequests(uint256 id) external view returns (DataTypes.UpdatePositionRequest memory);
    function swapOrders(uint256 id) external view returns (DataTypes.SwapOrder memory);
    function userLeverageOrderCount(address user) external view returns (uint256);
    function userLeverageOrders(address user, uint256 id) external view returns (uint256 orderId);
    function userSwapOrderCount(address user) external view returns (uint256);
    function userSwapOrders(address user, uint256 id) external view returns (uint256 orderId);
}

