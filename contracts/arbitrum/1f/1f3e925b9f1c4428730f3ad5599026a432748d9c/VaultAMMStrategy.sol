// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IVaultStrategy.sol";
import "./IVault.sol";
import "./Withdrawable.sol";

contract VaultAMMStrategy is Withdrawable, IVaultStrategy {
    //solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function batchSwap(
        address vault,
        IVault.SwapKind kind,
        IVault.BatchSwapStep[] calldata swaps,
        address[] calldata assets,
        IVault.FundManagement calldata funds,
        int256[] calldata limits,
        uint256 deadline
    ) external payable override {
        uint256 amount = msg.value;
        IVault.BatchSwapStep memory swapStep = swaps[0];
        if (assets[swapStep.assetInIndex] != address(0)) {
            IERC20(assets[swapStep.assetInIndex]).approve(vault, swapStep.amount);
        }
        IVault(vault).batchSwap{ value: amount }(kind, swaps, assets, funds, limits, deadline);
    }

    function swap(
        address vault,
        IVault.SingleSwap calldata singleSwap,
        IVault.FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external payable override {
        uint256 amount = msg.value;
        if (singleSwap.assetIn != address(0)) IERC20(singleSwap.assetIn).approve(vault, singleSwap.amount);
        IVault(vault).swap{ value: amount }(singleSwap, funds, limit, deadline);
    }
}

