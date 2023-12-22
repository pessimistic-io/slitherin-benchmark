// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.18;

interface IJackpotTool {
    function getCurrentUsdPrice(uint256 amount) external view returns (uint256 price);
}

