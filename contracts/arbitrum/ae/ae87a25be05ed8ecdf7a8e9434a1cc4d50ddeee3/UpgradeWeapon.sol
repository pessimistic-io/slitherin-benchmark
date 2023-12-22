//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC721.sol";

contract UpgradeWeapon is ERC721 {

    uint256 public tokenCounter;
    uint256 public tokenTypeCounter;
    mapping (uint256 => uint256) private _tokenTypes;
    mapping (uint256 => string) private _tokenTypeURIs;

    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {
        tokenCounter = 0;
        tokenTypeCounter = 0;
    }

    function mint(uint256 _tokenType) public {
        require(
            _tokenType < tokenTypeCounter,
            "ERC721Metadata: URI set of nonexistent token type"
        );  // Checks if the token type is valid
        _safeMint(msg.sender, tokenCounter);
        _tokenTypes[tokenCounter] = _tokenType;
        tokenCounter++;
    }

    function addTokenType(string memory _tokenURI) public virtual {
        _tokenTypeURIs[tokenTypeCounter] = _tokenURI;
        tokenTypeCounter++;
    }

    function setTokenTypeURI(uint256 _tokenType, string memory _tokenURI) public virtual {
        require(
            _tokenType < tokenTypeCounter,
            "ERC721Metadata: URI set of nonexistent token type"
        );  // Checks if the token type is valid
        _tokenTypeURIs[_tokenType] = _tokenURI;
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns(string memory) {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI set of nonexistent token ID"
        ); // Checks if the token ID is valid
        return _tokenTypeURIs[_tokenTypes[_tokenId]];
    }
    
}
