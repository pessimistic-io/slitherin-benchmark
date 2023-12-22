// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRNG {
    function generateNextRandomVariable() external returns (uint256);
    function generateModulo(uint256 lo, uint256 hi) external returns (uint256);
    function shuffleRandomNumbers() external;
    function generateMultiple(uint256 count) external returns (uint256[] memory);
    function getModulo(uint256 val, uint256 lo, uint256 hi) external pure returns (uint256);
}
