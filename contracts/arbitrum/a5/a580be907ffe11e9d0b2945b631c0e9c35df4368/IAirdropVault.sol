// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IAirdropVaultDef {
    error ZeroAddressSet();

    event WithdrawEmergency(
        address indexed to,
        address degenToken,
        uint256 degenAmount,
        uint256 nativeAmount
    );
}

interface IAirdropVault is IAirdropVaultDef {
    function rewardDegen(address to, uint256 amount) external; // send degen reward

    function rewardNative(address to, uint256 amount) external; // send native reward

    function withdrawEmergency(address to) external;
}

