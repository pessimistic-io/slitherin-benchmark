// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

/// @title IJonesDaoAdapter
/// @author Savvy DeFi
interface IJonesDaoAdapter {
    function stableVault() external view returns (address);

    function vaultRouter() external view returns (address);

    function depositStable(uint256 _assets, bool _compound) external;
}

