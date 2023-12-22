// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {BatchGatewayOrder, FulfillRFQOrder, BatchRFQOrder} from "./SocketStructs.sol";

/**
 * @title ISocketMarketplace
 * @notice Interface for Socket Marketplace Contract.
 * @author reddyismav.
 */
interface ISocketMarketplace {
    // Gateway extract function that sends funds through gateway.
    function batchExtractAndBridge(
        BatchGatewayOrder calldata batchGateway
    ) external payable;

    // RFQ Extract function that uses RFQ order system off chain.
    function batchExtractRFQ(BatchRFQOrder calldata batchRfq) external payable;

    // Fulfill Batch RFQ that fulfills user orders
    function fulfillBatchRFQ(
        FulfillRFQOrder[] calldata fulfillOrders
    ) external payable;

    // Settle RFQ Orders.
    function settleRFQOrders(
        bytes32[] calldata orderHashes,
        uint256 msgValue,
        uint256 destGasLimit,
        uint256 srcChainId
    ) external payable;
}

