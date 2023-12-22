// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC721.sol";
import "./Ownable.sol";

contract PositionToken is ERC721, Ownable {
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    function burn(uint256 id) external onlyOwner returns (bool) {
        _burn(id);
        return true;
    }

    function mint(address account, uint256 id) external onlyOwner returns (bool) {
        _mint(account, id);
        return true;
    }
}

