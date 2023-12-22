// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IVaultStrategy.sol";
import "./IVault.sol";
import "./Withdrawable.sol";

contract VaultAMMStrategy is Withdrawable, IVaultStrategy {
    address public vault;

    receive() external payable {}

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function batchSwap(
        IVault.SwapKind kind,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        IVault.FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable override {
        uint256 amount = msg.value;
        for (uint256 i = 0; i < swaps.length; i++) {
            IVault.BatchSwapStep memory swapStep = swaps[i];
            if (assets[swapStep.assetInIndex] != address(0)) {
                IERC20(assets[swapStep.assetInIndex]).approve(vault, swapStep.amount);
            }
        }
        IVault(vault).batchSwap{value: amount}(kind, swaps, assets, funds, limits, deadline);
    }

    function swap(
        IVault.SingleSwap memory singleSwap,
        IVault.FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable override {
        uint256 amount = msg.value;
        if (singleSwap.assetIn != address(0))
            IERC20(singleSwap.assetIn).approve(vault, singleSwap.amount);
        IVault(vault).swap{value: amount}(singleSwap, funds, limit, deadline);
    }
}

