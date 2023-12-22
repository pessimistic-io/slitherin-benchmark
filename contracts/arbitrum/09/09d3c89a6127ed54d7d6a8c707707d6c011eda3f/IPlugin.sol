// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IPlugin {
    enum ActionType {
        // Action types
        Stake,
        Unstake,
        GetStakedAmountLD,
        GetTotalAssetsMD
    }

    struct lzTxObj {
        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        bytes dstNativeAddr;
    }

    function execute(ActionType _actionType, bytes calldata _payload) external returns (bytes memory);
}
