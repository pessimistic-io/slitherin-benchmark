// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IBridgeAdapter} from "./IBridgeAdapter.sol";
import {IFundsCollector} from "./IFundsCollector.sol";

abstract contract BridgeAdapter is IBridgeAdapter {
    using SafeERC20 for IERC20;

    mapping(bytes32 traceId => uint256 blockNumber) public bridgeFinishedBlock;

    function _generateTraceId() internal returns (bytes32 traceId) {
        traceId = keccak256(
            abi.encodePacked(
                address(this),
                msg.sender,
                msg.data,
                block.timestamp
            )
        );
        emit BridgeStarted(traceId);
    }

    function _finishBridgeToken(
        bytes32 traceId,
        address token,
        uint256 amount,
        address fundsCollector,
        address withdrawalAddress,
        address owner
    ) internal {
        IERC20(token).safeIncreaseAllowance(fundsCollector, amount);
        IFundsCollector(fundsCollector).collectFunds(
            withdrawalAddress,
            owner,
            token,
            amount
        );

        bridgeFinishedBlock[traceId] = block.number;
        emit BridgeFinished(traceId, token, amount);
    }
}

