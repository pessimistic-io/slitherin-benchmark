// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface ISmolverseFlywheelVault {
    function isOwner(
        address tokenAddress,
        uint256 tokenId,
        address user
    ) external view returns(bool);

    function getAllowanceForToken(address token) external view returns (uint256 amount);

    function remainingStakeableAmount(address user) external view returns (uint256 remaining);

    function getStakedAmount(address user) external view returns (uint256 amount);
}

