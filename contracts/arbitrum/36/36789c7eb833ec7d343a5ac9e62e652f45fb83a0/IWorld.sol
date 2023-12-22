// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWorld {

    function ownerForStakedToad(uint256 _tokenId) external view returns(address);

    function locationForStakedToad(uint256 _tokenId) external view returns(Location);

    function balanceOf(address _owner) external view returns (uint256);
}

enum Location {
    NOT_STAKED,
    WORLD,
    HUNTING_GROUNDS,
    CRAFTING
}
