// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.10;

import "./ERC20.sol";

contract Crab is ERC20 {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error TRANSFER_PAUSED();

    /**
     * @dev Sets the values for {name} and {symbol}.
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    /**
     * @dev See {IERC20-transfer}.
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (to == address(0)) _burn(msg.sender, amount);
        else revert TRANSFER_PAUSED();
    }

    /**
     * @dev See {IERC20-transferFrom}.
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (to == address(0)) {
            // msking sure user has allowance to burn
            _spendAllowance(from, msg.sender, amount);
            _burn(from, amount);
        } else revert TRANSFER_PAUSED();
    }
}

