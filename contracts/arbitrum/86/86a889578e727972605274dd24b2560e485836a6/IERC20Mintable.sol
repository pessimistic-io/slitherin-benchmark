// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 expanded to include mint functionality
 * @dev
 */
interface IERC20Mintable {
    /**
     * @dev mints `amount` to `receiver`
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits an {Minted} event.
     */
    function mint(address receiver, uint256 amount) external;
}

