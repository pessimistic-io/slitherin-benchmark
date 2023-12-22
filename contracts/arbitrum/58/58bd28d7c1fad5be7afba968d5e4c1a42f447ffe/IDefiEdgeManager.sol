// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IDefiEdgeManager {
    function managementFeeRate() external view returns (uint256);
}
