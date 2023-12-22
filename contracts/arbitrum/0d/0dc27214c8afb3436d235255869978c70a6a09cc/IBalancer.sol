// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFlashLoanRecipient} from "./IFlashLoanRecipient.sol";

interface IBalancer {
    function flashLoan(
        IFlashLoanRecipient recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

