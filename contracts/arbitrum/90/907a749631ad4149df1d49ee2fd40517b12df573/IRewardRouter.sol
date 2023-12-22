// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IRewardRouter {
    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
}

