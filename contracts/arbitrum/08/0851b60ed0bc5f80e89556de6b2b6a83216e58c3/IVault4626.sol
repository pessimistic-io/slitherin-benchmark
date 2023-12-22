// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IVault4626 {
    function balanceOf(address) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);
    function deposit(uint256 amount, address to) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}

