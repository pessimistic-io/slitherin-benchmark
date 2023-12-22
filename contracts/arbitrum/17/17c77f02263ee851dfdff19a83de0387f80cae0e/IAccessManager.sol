// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IAccessManager {
    function hasAccess(uint256 poolId, address user)
        external
        view
        returns (bool);

    function participate(
        uint256 poolId,
        address user,
        uint256 weeklyInvestment
    ) external;
}

