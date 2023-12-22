// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./Strings.sol";
import "./mock_ERC721A.sol";

contract MockERC721A is ERC721A {
    address public allowedMinter;
    constructor()
        ERC721A("MockERC721A", "MockERC721A")

    {
        allowedMinter = msg.sender;
    }

    function mint() external returns (uint256) {
        // `_mint`'s second argument now takes in a `quantity`, not a `tokenId`.
        require(msg.sender == allowedMinter, "you are not allowed minter");
        _mint(allowedMinter, 1);
        return _nextTokenId() - 1;
    }

    function mintTo(address recipient) external {
        require(msg.sender == allowedMinter, "you are not allowed minter");
        _mint(recipient, 1);
    }

    function burn(uint256 tokenId) external {
        require(msg.sender == allowedMinter, "you are not allowed minter");
        _burn(tokenId);
    }

    function setAllowedMinter(address _allowedMinter) external {
        require(msg.sender == allowedMinter, "you are not allowed minter");
        allowedMinter = _allowedMinter;
    }
}

