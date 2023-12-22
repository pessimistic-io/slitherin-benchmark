// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IVaultDef {
    event WithdrawEmergency(
        address indexed to,
        address erc20Token,
        uint256 erc20Amount,
        uint256 nativeAmount
    );
}

interface IVault is IVaultDef {}

