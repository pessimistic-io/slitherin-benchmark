// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./SafeERC20.sol";
import "./IERC20.sol";

abstract contract BaseRouter {
    using SafeERC20 for IERC20;

    address internal immutable _self;

    constructor() {
        _self = address(this);
    }

    /** @notice Transfers in an ERC20 token */
    function _transferIn(address token, uint256 amount) internal {
        IERC20(token).safeTransferFrom(msg.sender, _self, amount);
    }

    /** @return the {token} balance of this contract */
    function _balanceOfSelf(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(_self);
    }
}

