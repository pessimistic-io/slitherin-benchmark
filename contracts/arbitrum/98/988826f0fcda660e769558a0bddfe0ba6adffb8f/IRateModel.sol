// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRateModel {
    function rate(uint256) external view returns (uint256);
    function kink() external view returns (uint256);
    function base() external view returns (uint256);
    function low() external view returns (uint256);
    function high() external view returns (uint256);
}

