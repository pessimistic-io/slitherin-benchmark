// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface ISmartVault {
    function depositAndInvest(uint256 amount) external;

    function totalSupply() external view returns (uint256 amount);

    function previewWithdraw(
        uint256 amount
    ) external view returns (uint256 shares);

    function withdraw(uint256 shares) external;

    function underlying() external view returns (address);
}

