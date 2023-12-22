// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IBridgeAdapter} from "./IBridgeAdapter.sol";
import {ITokenWithMessageReceiver} from "./ITokenWithMessageReceiver.sol";

abstract contract BridgeAdapter is IBridgeAdapter {
    using SafeERC20 for IERC20;

    mapping(bytes32 traceId => uint256 blockNumber) public bridgeFinishedBlock;

    function _generateTraceId() internal returns (bytes32 traceId) {
        traceId = keccak256(
            abi.encodePacked(
                address(this),
                msg.sender,
                msg.data,
                block.timestamp // solhint-disable-line not-rely-on-time
            )
        );
        emit BridgeStarted(traceId);
    }

    function _finishBridgeToken(
        address token,
        uint256 amount,
        bytes memory payload
    ) internal {
        (
            bytes32 traceId,
            address receiver,
            bytes memory message
        ) = _parsePayload(payload);

        IERC20(token).safeIncreaseAllowance(receiver, amount);
        ITokenWithMessageReceiver(receiver).receiveTokenWithMessage(
            token,
            amount,
            message
        );

        bridgeFinishedBlock[traceId] = block.number;
        emit BridgeFinished(traceId, token, amount);
    }

    function _generatePayload(
        bytes32 traceId,
        address receiver,
        bytes memory message
    ) internal pure returns (bytes memory payload) {
        payload = abi.encode(traceId, receiver, message);
    }

    function _parsePayload(
        bytes memory payload
    )
        internal
        pure
        returns (bytes32 traceId, address receiver, bytes memory message)
    {
        (traceId, receiver, message) = abi.decode(
            payload,
            (bytes32, address, bytes)
        );
    }
}

