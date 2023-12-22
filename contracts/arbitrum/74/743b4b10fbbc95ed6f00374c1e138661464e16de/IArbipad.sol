// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IArbipad {
    struct User {
        uint256 tier;
        uint256 totalAllocation;
    }

    function userInfo(address _address) external view returns (User memory);

    function tokenAddress() external view returns (address);

    function totalRaisedFundInAllTier() external view returns (uint256);
}

