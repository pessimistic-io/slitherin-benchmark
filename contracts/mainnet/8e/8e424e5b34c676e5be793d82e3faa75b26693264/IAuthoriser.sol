// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.10;

interface IAuthoriser {
    // function forEditing(address, string memory) external view returns (bool);
    function canRegister(bytes32 node, address sender, bytes[] memory blob) external view returns (bool);
}

