//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

interface InterfaceArbiDogsNft {
    event Mint(address indexed user, uint256 tokenId);
    event Reveal(uint256[] _tokenIds, string[] _hashes);
    event SetBaseURI(string _uri);
    event SetDefaultIpfsFile(string _file);

    function setBaseURI(string memory _uri) external;

    function mint(address user) external;
}

