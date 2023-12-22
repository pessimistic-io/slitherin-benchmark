// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPlutusDepositor {
    function sGLP() external view returns (address);
    function fsGLP() external view returns (address);
    function vault() external view returns (address);
    function minter() external view returns (address);
    function deposit(uint256 amount) external;
    function depositFor(address user, uint256 amount) external;
    function redeem(uint256 amount) external;
}

interface IPlutusFarm {
    function pls() external view returns (address);
    function userInfo(address) external view returns (uint96, int128);
    function pendingRewards(address) external view returns(uint256);
    function deposit(uint96) external;
    function withdraw(uint96) external;
    function harvest() external;
}

interface IPlutusVault {
    function convertToAssets(uint256 shares) external view returns (uint256 assets);
}

