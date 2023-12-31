// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title IJonesDaoVaultRouter
/// @author Savvy DeFi
interface IJonesDaoVaultRouter {
    function rewardCompounder(address _asset) external view returns (address);

    function stableWithdrawalSignal(uint256 _shares, bool _compound) external;
}

