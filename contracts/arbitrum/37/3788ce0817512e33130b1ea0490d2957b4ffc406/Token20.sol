//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import "./Ownable.sol";
import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract Token20 is ERC20, ERC20Burnable, Ownable {
    uint8 _decimals;

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals_
    ) ERC20(tokenName, tokenSymbol) {
        _transferOwnership(msg.sender);
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

