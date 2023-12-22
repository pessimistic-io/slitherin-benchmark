// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IAddToPacksAllowList {
        function addToAllowlist(uint256[] memory packIDs, address[] memory accounts, uint256[] memory amounts) external;
}
