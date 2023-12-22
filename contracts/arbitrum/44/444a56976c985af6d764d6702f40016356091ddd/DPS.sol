//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./Strings.sol";

contract DPS is Ownable, ERC721Enumerable {
    uint256 public constant MAX_SUPPLY = 3000;

    bool mintingStopped = false;

    uint256[] private mintedIds;

    address private minter;

    mapping(uint256 => string) private _tokenURIs;

    constructor() ERC721("Damned Pirates Society", "DPS") {}

    string private baseUri = "https://damnedpiratessociety.io/api/tokens/";

    function setTokenUri(uint256 _tokenId, string memory _tokenURI) external onlyOwner {
        _setTokenURI(_tokenId, _tokenURI);
    }

    function mint(address _owner, uint256 _tokenId) external {
        require(msg.sender == owner() || msg.sender == minter, "Only owner can mint");
        require(!mintingStopped, "Minting has been stopped");
        require(MAX_SUPPLY >= totalSupply(), "MAX Supply Reached");
        require(_tokenId <= MAX_SUPPLY, "Token Id out of bounds");
        mintedIds.push(_tokenId);
        _safeMint(_owner, _tokenId);
    }

    function exists(uint256 _tokenId) public view returns (bool) {
        return _exists(_tokenId);
    }

    //Call this when minting period finishes, it's irreversible, once called the minting can not be enabled
    function stopMinting() external onlyOwner {
        require(!mintingStopped, "Minting already stopped");
        mintingStopped = true;
    }

    function isStopped() external view returns (bool) {
        return mintingStopped;
    }

    function _safeMint(address _owner, uint256 _tokenId) internal override {
        super._safeMint(_owner, _tokenId);
        _setTokenURI(_tokenId, string(abi.encodePacked(baseUri, Strings.toString(_tokenId))));
    }

    function setBaseUri(string memory _newBaseUri) external onlyOwner {
        baseUri = _newBaseUri;
    }

    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "Minter can not be address 0");
        minter = _minter;
    }

    function getMaxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    function getMintedTokens() external view returns (uint256[] memory) {
        return mintedIds;
    }

    function tokensOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }
}

