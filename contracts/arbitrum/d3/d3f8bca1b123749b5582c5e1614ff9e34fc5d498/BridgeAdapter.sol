// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ArbSys} from "./ArbSys.sol";

import {IBridgeAdapter} from "./IBridgeAdapter.sol";
import {ITokenWithMessageReceiver} from "./ITokenWithMessageReceiver.sol";

abstract contract BridgeAdapter is IBridgeAdapter {
    using SafeERC20 for IERC20;

    /// @inheritdoc IBridgeAdapter
    mapping(bytes32 traceId => uint256 blockNumber) public bridgeFinishedBlock;

    /// @inheritdoc IBridgeAdapter
    function sendTokenWithMessage(
        Token calldata token,
        Message calldata message
    ) external payable returns (bytes32 traceId) {
        traceId = keccak256(
            abi.encodePacked(
                address(this),
                msg.sender,
                msg.data,
                block.timestamp // solhint-disable-line not-rely-on-time
            )
        );
        _startBridge(token, message, traceId);
    }

    function _startBridge(
        Token calldata token,
        Message calldata message,
        bytes32 traceId
    ) internal virtual;

    function _finishBridge(
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

        bridgeFinishedBlock[traceId] = _getBlockNumber();
        emit BridgeFinished(traceId, token, amount);
    }

    // solhint-disable-next-line named-return-values
    function _getBlockNumber() internal view returns (uint256) {
        if (block.chainid == 42161) {
            return ArbSys(address(100)).arbBlockNumber();
        }
        return block.number;
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

