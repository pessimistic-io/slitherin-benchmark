// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IAssetPool {
    error InvalidAccess();

    function isOperator(address operator) external view returns (bool);

    function withdraw(address asset, uint256 amount, address recipient) external;
}

