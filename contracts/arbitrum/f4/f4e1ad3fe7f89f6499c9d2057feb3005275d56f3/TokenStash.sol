/**
 * @notice
 * Facet is used to hold tokens for the vault contracts.
 *
 * When a vault contract receives some request (e.g Deposit request), then it may want to transfer the tokens into
 * the vault's balance right away. In order to avoid some reentrancy/spam attack (since it is processed by an offchain handler first).
 *
 * In order to receive the desired tokens right away, and not mess up with the execution of other operations (e.g mixing balances),
 * a vault may send tokens to the Yieldchain diamond - this facet specifically. It will keep track of it's debt per token, per vault,
 * and allow withdrawals to them accordingly
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Modifiers.sol";
import "./storage_TokenStash.sol";

contract TokenStashFacet is Modifiers {
    // ==================
    //      GETTERS
    // ==================
    /**
     * Get a strategy's token's stash amount
     * @param vault - The vault to check
     * @param token - The token to check
     * @return stashedAmount - The token amount stashed by this strategy
     */
    function getStrategyStash(
        Vault vault,
        ERC20 token
    ) external view returns (uint256 stashedAmount) {
        stashedAmount = TokenStashStorageLib
            .getTokenStasherStorage()
            .strategyStashes[vault][token];
    }

    // ==================
    //     FUNCTIONS
    // ==================
    /**
     * @notice Stash a token by a vault
     * Note that the msg.sender should be the vault address
     * @param tokenAddress - The token address to receive from it.
     * Note that the desired token should be approved to us
     * @param amount - The amount to receive
     */
    function stashTokens(
        address tokenAddress,
        uint256 amount
    ) external onlyVaults {
        TokenStashStorageLib.addToStrategyStash(
            Vault(msg.sender),
            ERC20(tokenAddress),
            amount
        );
    }

    /**
     * @notice Withdraw a token from a vault's stash
     * Note that the msg.sender should be the vault address
     * @param tokenAddress - The token address to withdraw
     * @param amount - The amount to withdraw
     */
    function unstashTokens(
        address tokenAddress,
        uint256 amount
    ) external onlyVaults {
        TokenStashStorageLib.removeFromStrategyStash(
            Vault(msg.sender),
            ERC20(tokenAddress),
            amount
        );
    }
}

