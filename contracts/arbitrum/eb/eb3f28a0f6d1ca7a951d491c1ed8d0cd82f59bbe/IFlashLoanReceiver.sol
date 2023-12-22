// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.4;

interface IFlashLoanReceiver {
    function executeOperation(
        uint256 _amount,
        uint256 _fee,
        bytes calldata _params
    ) external;
}

