// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./IFlashLoanRecipient.sol";

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;

    function borrow(address token, uint256 amount) external;

    function repay(address token, uint256 amount) external;
}

