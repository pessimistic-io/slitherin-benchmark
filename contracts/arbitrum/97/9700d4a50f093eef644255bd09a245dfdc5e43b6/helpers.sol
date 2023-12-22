// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";

abstract contract Helpers {
    /// @dev We choose to not user OZ interface for gas optimisation purposes
    /// @dev This router doesn't need to be safe on token transfers as its storage nevers depends on transfer parameters
    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}

