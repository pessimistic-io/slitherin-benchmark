// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface InvestmentPoolsInterface {
    function getUserBalancePerPool(
        address addr,
        uint256 poolId
    ) external view returns (uint256);

    function getAmountRaisedPerPool(
        uint256 poolId
    ) external view returns (uint256);

    function creatorPerPoolId(uint256 poolId) external view returns (address);

    function checkIfUserHasInvestedInPoolId(
        address user,
        uint256 poolId
    ) external view returns (bool);
}

