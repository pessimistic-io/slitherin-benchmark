// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IUpshotConsumer {
    function requestIdResult(bytes32 _requestId) external view returns (uint256);

    function requestPrice(uint256 _assetId) external returns (bytes32);
}

