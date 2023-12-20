// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Pausable.sol";
import "./ERC20Base.sol";

/**
 * @dev ERC20 token with pausable token transfers, minting and burning.
 *
 * Useful for scenarios such as preventing trades until the end of an evaluation
 * period, or having an emergency switch for freezing all token transfers in the
 * event of a large bug.
 */
abstract contract ERC20Pausable is ERC20Base, Pausable {
    /**
     * @dev See {ERC20-_beforeTokenTransfer}.
     *
     * Requirements:
     *
     * - the contract must not be paused.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        require(!paused(), "ERC20Pausable: transfer paused");
        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @dev Pause the contract
     * Access restriction must be overriden in derived class
     */
    function pause() external virtual {
        _pause();
    }

    /**
     * @dev Resume the contract
     * Access restriction must be overriden in derived class
     */
    function resume() external virtual {
        _unpause();
    }
}

