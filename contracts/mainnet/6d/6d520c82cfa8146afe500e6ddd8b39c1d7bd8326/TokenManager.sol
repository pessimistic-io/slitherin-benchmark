// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
// pragma experimental SMTChecker;

import {Ownable} from "./Ownable.sol";
import {TransferHelper} from "./TransferHelper.sol";

contract TokenManager is Ownable {
    /* receive function */

    receive() external payable {}

    /* admin functions */

    function transferERC20(
        address token,
        address to,
        uint256 value
    ) external onlyOwner {
        TransferHelper.safeTransfer(token, to, value);
    }

    function transferFromERC20(
        address token,
        address from,
        address to,
        uint256 value
    ) external onlyOwner {
        TransferHelper.safeTransferFrom(token, from, to, value);
    }

    function approveERC20(
        address token,
        address to,
        uint256 value
    ) external onlyOwner {
        TransferHelper.safeApprove(token, to, value);
    }

    function transferETH(address to, uint256 value) external onlyOwner {
        TransferHelper.safeTransferETH(to, value);
    }
}

