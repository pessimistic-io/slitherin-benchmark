/**
    TokiBot
    Toki Bot is a Telegram bot that was created with the aim of making contract creation accessible to everyone.

    Website: https://tokibot.xyz/
    Twitter: https://twitter.com/tokigenerator
    Telegram: t.me/tokigenerator
    Telegram Bot: t.me/tokigenerator_bot
**/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20.sol";

/**
 * @title ERC20Custom
 * @dev This contract implements the ERC20 standard token with additional custom features.
 */
contract DeployedByTokiERC20 is ERC20 {
    /**
     * @dev Constructor to create a new ERC20Custom token.
     * @param name The name of the token.
     * @param symbol The symbol (ticker) of the token.
     * @param totalSupply The total supply of tokens to be minted and assigned to the contract deployer.
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 totalSupply
    ) payable ERC20(name, symbol) {
        _mint(msg.sender, totalSupply);
    }
}
