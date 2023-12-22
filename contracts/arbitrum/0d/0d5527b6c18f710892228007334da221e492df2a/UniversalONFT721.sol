// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./ONFT721.sol";

import "./Strings.sol";

/// @title Interface of the UniversalONFT standard
contract UniversalONFT721 is ONFT721 {
    uint public nextMintId;

    /// @notice Constructor for the UniversalONFT
    /// @param _name the name of the token
    /// @param _symbol the token symbol
    constructor(
      string memory _name,
      string memory _symbol,
      address _layerZeroEndpoint
    ) ONFT721(_name, _symbol, _layerZeroEndpoint) {}

    /// @notice Mint admin NFTs
    function adminMint() external onlyOwner {
        uint newId = nextMintId;
        nextMintId++;
        _safeMint(msg.sender, newId);
    }

    /// @notice Set base uri
    function adminSetURI(string memory URI) external onlyOwner {
        baseURI = URI;
    }

    /// @notice Get token uri
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, Strings.toString(tokenId), ".json")) : "";
    }
}
