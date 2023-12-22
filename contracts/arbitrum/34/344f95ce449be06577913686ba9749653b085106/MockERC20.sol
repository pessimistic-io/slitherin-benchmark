// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "./ERC20.sol";
import { Ownable } from "./Ownable.sol";

contract MockERC20 is ERC20, Ownable {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint256 supply,
        uint8 decimals_
    ) ERC20(name, symbol) Ownable() {
        _mint(msg.sender, supply);
        _decimals = decimals_;
    }

    function mintTokens(uint256 _amount) external onlyOwner {
        _mint(msg.sender, _amount);
    }

    function mint(address to_, uint256 _amount) external onlyOwner {
        _mint(to_, _amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

