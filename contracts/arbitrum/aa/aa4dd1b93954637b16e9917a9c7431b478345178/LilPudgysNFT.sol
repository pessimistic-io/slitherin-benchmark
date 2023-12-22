// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import "./ERC721.sol";
import "./Ownable.sol";
import "./AccessControl.sol";

contract LilPudgysNFT is ERC721, Ownable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC721("LilPudgys", "LP") public {
        _setupRole(MINTER_ROLE, msg.sender);
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "LilPudgys: caller is not the minter");
        _;
    }

    function mint(address to, uint256 tokenId) public onlyMinter returns (bool) {
        _mint(to, tokenId);
        return true;
    }

    function setMinterRole(address minter) external onlyOwner {
        _setupRole(MINTER_ROLE, minter);
    }
}

