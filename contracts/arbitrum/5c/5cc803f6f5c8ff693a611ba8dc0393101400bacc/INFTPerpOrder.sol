// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;
import { Decimal } from "./Decimal.sol";
import { SignedDecimal } from "./SignedDecimal.sol";
import { IAmm } from "./IAmm.sol";
import "./Structs.sol";

interface INFTPerpOrder {
    event OrderCreated(bytes32 indexed orderHash, bytes orderDetails);
    event OrderFulfilled(bytes32 indexed orderhash);
    event FailedToFulfill(bytes reason);
    event SetManagementFee(uint256 _fee);
    event OrderCancelled(bytes32 indexed orderHash);

    function createOrder(
        IAmm _amm,
        Structs.OrderType _orderType, 
        uint64 _expirationTimestamp,
        uint256 _triggerPrice,
        Decimal.decimal memory _slippage,
        Decimal.decimal memory _leverage,
        Decimal.decimal memory _quoteAssetAmount
    ) external payable returns(bytes32);

    function fulfillOrder(bytes32 _orderHash) external;

    function cancelOrder(bytes32 _orderHash) external;

    function hasEnoughAllowances(bytes32[] memory _orders) external returns(bool[] memory);

    function canFulfillOrder(bytes32 _orderhash) external view returns(bool);

}
