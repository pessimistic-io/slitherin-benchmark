// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IVault {
    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );

    event Fees(uint256 t0,uint256 t1);

    function deposit(uint256 amount, address receiver) external;

    function withdraw(
        uint256 amount,
        address receiver
    ) external returns (uint256 shares);

    function harvest() external;

    function pauseAndWithdraw() external;

    function unpauseAndDeposit() external;

    function emergencyExit(uint256 amount, address receiver) external;

    function changeAllowance(address token, address to) external;

    function pauseVault() external;

    function unpauseVault() external;

    function asset() external view returns (address);
}

