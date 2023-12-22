// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IOlive {
    function deposit(uint256 amount) external;
    function accountBalance(address _account)
        external
        view
        returns (
            uint256 balance,
            uint256 balanceA,
            uint256 balanceB,
            uint256 sharesBalance
        );
    function withdrawInstantly(uint256 amount) external;
}
