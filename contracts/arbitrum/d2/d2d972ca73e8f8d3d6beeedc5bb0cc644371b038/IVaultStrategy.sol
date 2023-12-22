// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IVault.sol";

interface IVaultStrategy {
    function batchSwap(
        address vault,
        IVault.SwapKind kind,
        IVault.BatchSwapStep[] calldata swaps,
        address[] calldata assets,
        IVault.FundManagement calldata funds,
        int256[] calldata limits,
        uint256 deadline
    ) external payable;

    function swap(
        address vault,
        IVault.SingleSwap calldata singleSwap,
        IVault.FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external payable;
}

