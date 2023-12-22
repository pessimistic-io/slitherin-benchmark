// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWorld {

    function ownerForStakedToad(uint256 _tokenId) external view returns(address);

    function locationForStakedToad(uint256 _tokenId) external view returns(Location);
}

enum Location {
    NOT_STAKED,
    WORLD,
    HUNTING_GROUNDS,
    ADVENTURE
}
