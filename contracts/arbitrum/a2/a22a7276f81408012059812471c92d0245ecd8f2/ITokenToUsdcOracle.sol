// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.5.0;

interface ITokenToUsdcOracle {
    function usdcAmount(uint256 tokenAmount) external view returns (uint256 usdcAmount);
}
