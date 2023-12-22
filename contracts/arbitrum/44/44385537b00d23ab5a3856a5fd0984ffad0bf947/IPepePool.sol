// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPepePool {
    function payout(address user, address betToken, uint256 amount, uint256 betId) external;

    function setNewPepeBetAddress(address newPepeBet) external;

    function setNewServiceWallet(address newServiceWallet) external;

    function fundServiceWallet(uint256 amount, address token) external;

    function withdraw(uint256 amount, address token) external;
}

