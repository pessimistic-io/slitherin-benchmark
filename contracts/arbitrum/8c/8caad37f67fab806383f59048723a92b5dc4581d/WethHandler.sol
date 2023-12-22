//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "./AddressUpgradeable.sol";
import "./IWETH9.sol";

abstract contract WethHandler {
    using AddressUpgradeable for address payable;

    error OnlyFromWETH(address weth, address sender);

    IWETH9 public immutable weth;

    constructor(IWETH9 _weth) {
        weth = _weth;
    }

    function wrapETH() external payable returns (uint256 wrapped) {
        wrapped = address(this).balance;
        weth.deposit{value: wrapped}();
    }

    function unwrapWETH(address payable to) external payable returns (uint256 unwrapped) {
        unwrapped = weth.balanceOf(address(this));
        // We don't wanna fail on 0 unwrap as some batch calls may add it just in case
        if (unwrapped != 0) {
            weth.withdraw(unwrapped);
            to.sendValue(unwrapped);
        }
    }

    /// @dev `weth.withdraw` will send ether using this function.
    receive() external payable {
        if (msg.sender != address(weth)) {
            revert OnlyFromWETH(address(weth), msg.sender);
        }
    }
}

