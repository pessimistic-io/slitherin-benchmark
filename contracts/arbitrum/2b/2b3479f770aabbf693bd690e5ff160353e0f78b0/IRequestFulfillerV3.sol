// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

interface IRequestFulfillerV3 {

    function minDepositAmount() external view returns(uint256);
    function minWithdrawAmount() external view returns(uint256);
}

