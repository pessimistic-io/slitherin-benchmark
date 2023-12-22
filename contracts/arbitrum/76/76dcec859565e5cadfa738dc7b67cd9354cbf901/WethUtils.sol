// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
import "./SafeERC20.sol";
import "./IWETH.sol";

library WethUtils {
    using SafeERC20 for IWETH;

    IWETH public constant weth = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH Arb1

    function isWeth(address token) internal pure returns (bool) {
        return address(weth) == token;
    }

    function wrap(uint256 amount) internal {
        weth.deposit{value: amount}();
    }

    function unwrap(uint256 amount) internal {
        weth.withdraw(amount);
    }

    function transfer(address to, uint256 amount) internal {
        weth.safeTransfer(to, amount);
    }
}

