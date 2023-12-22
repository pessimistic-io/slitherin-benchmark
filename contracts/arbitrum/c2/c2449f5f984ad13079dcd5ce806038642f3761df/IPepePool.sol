// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPepePool {
    function payout(address user, uint256 amount, uint256 betId) external;
}

