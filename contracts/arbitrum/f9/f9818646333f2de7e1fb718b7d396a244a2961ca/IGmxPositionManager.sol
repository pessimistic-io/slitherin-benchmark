// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGmxPositionManager {
    function setMaxGlobalSizes(
        address[] memory _tokens,
        uint256[] memory _longSizes,
        uint256[] memory _shortSizes
    ) external;

    function maxGlobalShortSizes(address _token) external view returns (uint256);
}
