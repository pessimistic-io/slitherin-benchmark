// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IComet {
    function borrowBalanceOf(address) external view returns (uint256);

    function supply(address asset, uint256 amount) external;

    function withdrawTo(
        address to,
        address asset,
        uint256 amount
    ) external;

    function userCollateral(address user, address asset)
        external
        view
        returns (uint128 balance, uint128);
}

interface ICompoundRewards {
    function claimTo(
        address comet,
        address src,
        address to,
        bool shouldAccrue
    ) external;
}

