// SPDX-License-Identifier: GPL-3.0

import "./IERC721.sol";

interface IFootyNouns is IERC721 {}

pragma solidity ^0.8.0;

contract FootyNames {
    IFootyNouns public tokenContract;

    mapping(uint256 => string) public footyNames;
    mapping(address => string) public clubNames;

    event ClubNamed(address indexed owner, string indexed name);
    event FootyNamed(
        address indexed owner,
        uint256 indexed tokenId,
        string indexed name
    );

    constructor(IFootyNouns _tokenContract) {
        tokenContract = _tokenContract;
    }

    function nameClubAndFooties(
        string memory newClubName,
        uint256[] memory tokenIds,
        string[] memory newNames
    ) external {
        require(tokenIds.length == newNames.length, "non-matching-length");
        clubNames[msg.sender] = newClubName;
        emit ClubNamed(msg.sender, newClubName);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(tokenContract.ownerOf(tokenIds[i]) == msg.sender);
            footyNames[tokenIds[i]] = newNames[i];
            emit FootyNamed(msg.sender, tokenIds[i], newNames[i]);
        }
    }

    function getFootyName(uint256 tokenId)
        external
        view
        returns (string memory name)
    {
        return footyNames[tokenId];
    }

    function getClubName(address _address)
        external
        view
        returns (string memory name)
    {
        return clubNames[_address];
    }
}

