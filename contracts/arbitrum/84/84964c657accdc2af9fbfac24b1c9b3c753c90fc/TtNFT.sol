// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "./ERC721Burnable.sol";
import "./Ownable.sol";
import "./Base64.sol";


contract TtNFT is ERC721Burnable, Ownable {
    using Strings for uint256;
    using Base64 for bytes;

    uint constant public genesisMaxTokenId = 2000;

    uint public genesisCounter = 0;
    string public baseURI = "";
    mapping(address => bool) private keeperMap;

    string public description;
    string public image;

    modifier onlyKeeper() {
        require(
            isKeeper(msg.sender),
            "caller is not the owner or keeper"
        );
        _;
    }

    constructor(string memory _image,string memory _description) ERC721("TT", "TT") {
        image = _image;
        description = _description;
    }

    function setKeeper(address addr) public onlyOwner {
        keeperMap[addr] = true;
    }

    function removeKeeper(address addr) public onlyOwner {
        keeperMap[addr] = false;
    }

    function isKeeper(address addr) public view returns (bool) {
        return keeperMap[addr];
    }

    function setBaseURI(string calldata _baseURIPrefix) external onlyOwner {
        baseURI = _baseURIPrefix;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function mint(address to, uint256 quantity) external onlyKeeper {
        uint startTokenId = genesisCounter;
        require(startTokenId + quantity <= genesisMaxTokenId, 'max genesis supply');
        for (uint i = 0; i < quantity; ++i) {
            ++startTokenId;
            _mint(to, startTokenId);
        }
        genesisCounter = startTokenId;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (bytes(baseURI).length > 0) {
            return super.tokenURI(tokenId);
        } else {
            _requireMinted(tokenId);
            string memory metadata = string(abi.encodePacked(
                    "{",
                    "\"tokenId\":\"", tokenId.toString(), "\",",
                    "\"name\":\"", name(), "\",",
                    "\"image\":\"", image, "\",",
                    "\"description\":\"", description, "\",",
                    "\"attributes\":[]",
                    "}"
                ));
            return string(abi.encodePacked(
                    "data:application/json;base64,",
                    bytes(metadata).encode()
                ));
        }
    }

    function tokensOfOwnerIn(address owner, uint256 start, uint256 stop) external view returns (uint256[] memory) {
        require(start < stop, 'InvalidQueryRange');
        if (start < 1) {
            start = 1;
        }
        if (stop > genesisCounter) {
            stop = genesisCounter;
        }
        uint256 ownerTokenCount = balanceOf(owner);
        if (start < stop) {
            uint256 rangeLength = stop - start;
            if (rangeLength < ownerTokenCount) {
                ownerTokenCount = rangeLength;
            }
        } else {
            ownerTokenCount = 0;
        }
        uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);

        uint256 currentTokenId = start;
        uint256 ownedTokenIndex = 0;

        while (ownedTokenIndex < ownerTokenCount && currentTokenId <= stop) {
            address currentTokenOwner = _ownerOf(currentTokenId);
            if (currentTokenOwner == owner) {
                ownedTokenIds[ownedTokenIndex++] = currentTokenId;
            }
            currentTokenId++;
        }
        // Downsize the array to fit.
        assembly {
            mstore(ownedTokenIds, ownedTokenIndex)
        }
        return ownedTokenIds;
    }

    function tokensOfOwner(address owner) public view returns (uint256[] memory){
        uint256 ownerTokenCount = balanceOf(owner);
        uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
        uint256 currentTokenId = 1;
        uint256 ownedTokenIndex = 0;

        while (ownedTokenIndex < ownerTokenCount && currentTokenId <= genesisCounter) {
            address currentTokenOwner = _ownerOf(currentTokenId);
            if (currentTokenOwner == owner) {
                ownedTokenIds[ownedTokenIndex++] = currentTokenId;
            }
            currentTokenId++;
        }
        return ownedTokenIds;
    }

}

