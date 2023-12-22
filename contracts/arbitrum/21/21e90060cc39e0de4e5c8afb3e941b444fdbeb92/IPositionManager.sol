// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPositionManager {
    function ownerOf(uint256 id) external view returns (address);
}

