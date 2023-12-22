// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";

import {TransferHelper} from "./TransferHelper.sol";
import {IWETH9} from "./IWETH9.sol";

abstract contract PeripheryPayments {

    address public immutable WETH9;

    constructor(address _WETH9) {
        WETH9 = _WETH9;
    }

    receive() external payable {
        require(msg.sender == WETH9, 'Not WETH9');
    }

    function receipt(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token != WETH9) {
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }

    function approve(
        address token,
        address spender,
        uint256 amount
    ) internal {
        if (IERC20(token).allowance(address(this), spender) <= amount) {
            TransferHelper.safeApprove(token, spender, type(uint256).max);
        }
    }
}

