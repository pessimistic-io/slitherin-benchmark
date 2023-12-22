// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

interface IOperatorRegistry {
    function isOperatorApprovedForAddress(
        address user,
        address operator,
        address forAddress
    ) external view returns (bool isApproved);
}

