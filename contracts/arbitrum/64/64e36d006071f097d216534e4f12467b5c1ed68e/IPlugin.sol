// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IPlugin {
    enum ActionType {
        // Action types
        Stake,
        Unstake,
        GetTotalAssetsMD,
        ClaimReward,
        SwapRemote
    }

    struct lzTxObj {
        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        bytes dstNativeAddr;
    }

    function execute(ActionType _actionType, bytes calldata _payload) external payable returns (bytes memory);

    function getStakedAmount(address _token) external view returns (uint256, uint256);

    function quoteSwapFee(uint16 _dstChainId) external view returns (uint256);
}
