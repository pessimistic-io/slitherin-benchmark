// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

interface IERC721TokenMinterFunctions {
    /**
     * Mint tokens.
     * @param to Address to mint tokens to.
     * @param amount Amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external;

    /**
     * Set name and symbol of token.
     * @param tokenName Name of token.
     * @param tokenSymbol Symbol of token.
     */
    function setNameAndSymbol(string memory tokenName, string memory tokenSymbol) external;
}

interface IERC721TokenMinterSignals {
    /**
     * Invalid initialization error.
     */
    error InvalidInitialization();
}

interface IERC721TokenMinter is IERC721TokenMinterFunctions, IERC721TokenMinterSignals {}

