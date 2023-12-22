// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC721} from "./ERC721.sol";
import {IERC721} from "./IERC721.sol";

import {Ownable} from "./Ownable.sol";

import "./ERC721URIStorage.sol";

contract MMDD is ERC721, Ownable {
    uint counter;

    string public baseURI;

    constructor(string memory baseURI_) ERC721("MMDoDe", "MMDD") {
        baseURI = baseURI_;
    }

    function setBaseURI(string memory baseURI_) public onlyOwner {
        baseURI = baseURI_;
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        return
            bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI)) : "";
    }

    function mint(uint num) external {
        for (uint i; i < num; i++) {
            _mint(msg.sender, counter);
            counter++;
        }
    }
}

