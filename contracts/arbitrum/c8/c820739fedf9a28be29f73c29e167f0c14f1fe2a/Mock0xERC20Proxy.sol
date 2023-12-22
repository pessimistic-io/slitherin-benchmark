/**
 * SPDX-License-Identifier: UNLICENSED
 */
pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

import {ERC20Interface} from "./ERC20Interface.sol";
import {SafeERC20} from "./SafeERC20.sol";

/**
 * @notice Mock 0x ERC20 Proxy

 */
contract Mock0xERC20Proxy {
    using SafeERC20 for ERC20Interface;

    function transferToken(
        address token,
        address from,
        address to,
        uint256 amount
    ) external {
        ERC20Interface(token).safeTransferFrom(from, to, amount);
    }
}

