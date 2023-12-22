// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC721.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";

contract XRenderAiCartoon is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    constructor() ERC721("XRender Ai XRenderAiCartoon", "XRender") {}

    function mint(string memory tokenURI) external onlyOwner returns (uint256) {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, tokenURI);
        return newItemId;
    }

    function getTokenIds() public view returns (uint256) {
        return _tokenIds.current();
    }
}

