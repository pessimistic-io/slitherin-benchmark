// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

interface IFiguresToken {
    /**
     * Initialize seed random variables used to render token
     * Can only be called by controller
     */
    function initializeSeed(uint256[] memory seed) external;

    /**
     * Mint a token with the given seed.
     * Can only be called by controller
     */
    function mint(
        uint256 tokenId,
        uint256 seed,
        address recipient
    ) external;

    /**
     * Render token based on seed
     */
    function render(uint256 seed, uint256 assetId)
        external
        view
        returns (string memory s);
}

