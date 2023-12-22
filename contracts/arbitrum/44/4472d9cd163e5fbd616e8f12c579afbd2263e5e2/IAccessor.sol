// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// @Dev See { MoonTouch }.
interface IAccessor {
    function mintBatch(address to, uint256 count, string[] calldata dnaList) external;
    function hasRole(bytes32 role, address target) external view returns (bool);
}

