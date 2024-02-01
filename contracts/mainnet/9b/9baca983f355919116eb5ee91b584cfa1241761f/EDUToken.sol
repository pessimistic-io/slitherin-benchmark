// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./AccessControl.sol";
import "./Counters.sol";
import "./IERC721Mintable.sol";

contract EDUToken is ERC721, AccessControl, IERC721Mintable {
    using Counters for Counters.Counter;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    Counters.Counter private _tokenIdCounter;

    uint128 public immutable MAX_SUPPLY;

    constructor(string memory name_, string memory symbol_, uint128 maxSupply_)
        ERC721(name_, symbol_)
    {
        MAX_SUPPLY = maxSupply_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function safeMint(address to)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 tokenId)
    {
        tokenId = _tokenIdCounter.current();

        require(tokenId < MAX_SUPPLY, "Reached max supply");
        require(balanceOf(to) == 0, "Cannot have more than 1");

        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

