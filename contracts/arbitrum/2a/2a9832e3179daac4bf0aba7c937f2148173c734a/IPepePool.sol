// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPepePool {
    function payout(address user, uint256 amount, uint256 betId) external;

    function setNewPepeBetAddress(address newPepeBet) external;

    function setNewServiceWallet(address newServiceWallet) external;

    function fundServiceWallet(uint256 amount) external;

    function withdraw(uint256 amount) external;
}

