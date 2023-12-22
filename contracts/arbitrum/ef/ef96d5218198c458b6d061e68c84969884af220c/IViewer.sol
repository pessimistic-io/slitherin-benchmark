//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IViewer {
    function getGlpRatioWithoutRetention(uint256 _amount) external view returns (uint256);
    function getUSDCRatio(uint256 _jUSDC) external view returns (uint256);
}

