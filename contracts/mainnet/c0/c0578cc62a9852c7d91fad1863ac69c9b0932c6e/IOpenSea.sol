pragma solidity ^0.8.6;
import "./Types.sol";

interface Seaport is Types {
    function matchOrders(
        Order[] calldata orders,
        Fulfillment[] calldata fulfillments
    ) external payable returns (Execution[] memory executions);

}

