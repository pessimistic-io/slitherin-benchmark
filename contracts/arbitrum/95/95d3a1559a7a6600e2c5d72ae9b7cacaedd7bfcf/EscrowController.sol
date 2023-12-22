// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Owned} from "./Owned.sol";
import {ERC721Enumerable} from "./ERC721Enumerable.sol";
import {IRenderer} from "./IRenderer.sol";

contract EscrowController is Owned(tx.origin), ERC721Enumerable 
{
    address renderer;
    uint96 public version = 1;
    address[] public escrows;

    constructor() ERC721Enumerable("GMX Escrow Ownership", "GEO") {

    }

    function setRenderer(address r) external onlyOwner
    {
        renderer = r;
    }

    function mint(address to, address escrow) external onlyOwner returns (uint256) {
        uint256 id = escrows.length;
        escrows.push(escrow);
        _safeMint(to, id);
        return id;
    }

    function burn(uint256 id) external {
        require(msg.sender == ownerOf(id), "BURN_NOT_ONWER");
        _burn(id);
    }

    function tokenURI(uint256 id) public view override returns (string memory)
    {
        address escrow = escrows[id];
        if (renderer == address(0))
            return "data:,";
        else{
            return IRenderer(renderer).tokenURI(id, escrow);
        }
    }
}

