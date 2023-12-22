// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IDragonTribute {
    // ============= Events ==============

    event Deposit(address indexed user, uint256 amountDeposited, uint256 amountMinted);
    event WithdrawMagic(address indexed withdrawer, address indexed recipient, uint256 amount);
    event SetMintRatio(uint256 ratio);
    event SetPaused(bool paused);

    // ============= User Operations ==============

    function deposit(uint256 _amount) external;

    function depositFor(uint256 _amount, address user) external;

    // ============= Owner Operations ==============

    function withdrawMagic(uint256 _amount, address to) external;

    function setMintRatio(uint256 _ratio) external;
}

