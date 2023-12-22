// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20Mintable.sol";
import "./IERC20.sol";

/**
 * @dev Interface of the ERC20 expanded to include mint and burn functionality
 * @dev
 */
interface IERC20MintableBurnable is IERC20Mintable, IERC20 {
    /**
     * @dev burns `amount` from `receiver`
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits an {BURN} event.
     */
    function burn(address _from, uint256 _amount) external;
}

