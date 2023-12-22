// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ITreasuryVault {
    function withdrawNative(uint256 amount) external;

    function depositERC20(uint256 amount, address asset) external;

    function withdrawERC20(address tokenAddress, uint256 amount) external;
}

