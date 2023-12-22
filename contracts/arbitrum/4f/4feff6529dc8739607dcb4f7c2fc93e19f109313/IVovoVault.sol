// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IVovoVault {
    function deposit(uint256 amount) external;
    function depositFor(uint256 amount, address account) external;
    function withdraw(uint256 shares) external;
}

