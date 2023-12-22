//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ERC721} from "./ERC721.sol";
import {ERC721Enumerable} from "./ERC721Enumerable.sol";
import {ERC721Burnable} from "./ERC721Burnable.sol";
import {Ownable} from "./Ownable.sol";
import {Counters} from "./Counters.sol";

contract WritePositionMinter is
    ReentrancyGuard,
    ERC721("AS-WritePosition", "ASWP"),
    ERC721Enumerable,
    ERC721Burnable,
    Ownable
{
    using Counters for Counters.Counter;

    /// @dev Token ID counter for write positions
    Counters.Counter private _tokenIdCounter;

    address public straddleContract;

    constructor() {
        straddleContract = msg.sender;
    }

    /// @dev Update straddle contract address
    function setStraddleContract(address _straddleContract) public onlyOwner {
        straddleContract = _straddleContract;
    }

    function mint(address to) public returns (uint256 tokenId) {
        require(
            msg.sender == straddleContract,
            "Only straddle contract can mint a write position token"
        );
        tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        return tokenId;
    }

    function burnToken(uint256 tokenId) public {
        burn(tokenId);
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

