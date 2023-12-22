// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IVault {
    function balanceOf(address) external view returns (uint256);

    function claimFees() external returns (uint256 claimed0, uint256 claimed1);

    function deposit(uint256 amount) external;

    function depositAll() external;

    function withdraw(uint256 amount) external;

    function withdrawAll() external;
}

