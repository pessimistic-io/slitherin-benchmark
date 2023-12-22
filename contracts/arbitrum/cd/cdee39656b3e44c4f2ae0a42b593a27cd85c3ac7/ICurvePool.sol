// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICurvePool {
    function coins(uint256 i) external view returns (address);
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 minDy) external payable;
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external payable;
}

