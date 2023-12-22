// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IUpshotConsumerV2 {
    function requestIdStatisticsNumber(bytes32 _requestId) external view returns (uint256);

    function requestStatisticsNumber(
        bytes32 _specId,
        uint256 _payment,
        string calldata _assetAddress
    ) external returns (bytes32 requestId);
}

