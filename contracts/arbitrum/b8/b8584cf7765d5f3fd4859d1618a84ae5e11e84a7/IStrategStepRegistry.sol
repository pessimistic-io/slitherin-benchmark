// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategyStepRegistry {
    function addSteps(address[] memory _steps) external;
    function getSteps(uint256[] memory _steps) external view returns (address[] memory);

    function stepsLength() external view returns (uint256);
    function steps(uint256 index) external view returns (address);
}
