// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract Token is ERC20, ERC20Burnable, Ownable {
    uint256 private constant INITIAL_SUPPLY = 888888888888888 * 10**18;

    constructor() ERC20("ZenShifuCoin", "ZSC") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function distributeTokens(address distributionWallet) external onlyOwner {
        uint256 supply = balanceOf(msg.sender);
        require(supply == INITIAL_SUPPLY, "Tokens already distributed");

        _transfer(msg.sender, distributionWallet, supply);
    }
}
