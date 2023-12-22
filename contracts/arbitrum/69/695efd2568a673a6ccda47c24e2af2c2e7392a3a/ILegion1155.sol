// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILegion1155 {
    // Transfers the legions at the given ID of the given amount.
    // Requires that the legions are pre-approved.
    //
    function safeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _amounts, bytes memory data) external;
}
