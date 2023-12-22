// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAdventure {

    function startAdventure(address _owner, uint256 _tokenId, string calldata _adventureName, uint256[] calldata _itemInputIds) external;

    function finishAdventure(address _owner, uint256 _tokenId) external;
}
