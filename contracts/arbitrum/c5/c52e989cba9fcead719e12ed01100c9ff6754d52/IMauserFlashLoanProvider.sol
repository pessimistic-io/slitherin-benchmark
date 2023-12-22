// SPDX-License-Identifier: Unlicense

pragma solidity >=0.8.0 <=0.8.19;

interface IMauserFlashLoanProvider {
    function multiSend(bytes memory transactions) external payable;
    function mauserFlashLoanAndMultiSend(address token, uint256 amount, bytes memory transactions) external payable;
}

