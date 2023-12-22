// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {ISubstitute} from "./ISubstitute.sol";

library SubstituteLibrary {
    using SafeERC20 for IERC20;

    function ensureBalance(ISubstitute substitute, address payer, uint256 amount) internal {
        uint256 balance = IERC20(address(substitute)).balanceOf(address(this));
        if (balance >= amount) {
            return;
        }
        address underlyingToken = substitute.underlyingToken();
        uint256 underlyingBalance = IERC20(underlyingToken).balanceOf(address(this));
        unchecked {
            amount -= balance;
            if (underlyingBalance < amount) {
                IERC20(underlyingToken).safeTransferFrom(payer, address(this), amount - underlyingBalance);
            }
        }
        IERC20(underlyingToken).approve(address(substitute), amount);
        substitute.mint(amount, address(this));
    }

    function burnAll(ISubstitute substitute, address to) internal {
        uint256 leftAmount = IERC20(address(substitute)).balanceOf(address(this));
        if (leftAmount > 0) {
            ISubstitute(substitute).burn(leftAmount, to);
        }
    }
}

