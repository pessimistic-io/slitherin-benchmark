// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./IAssetConverter.sol";
import "./ERC20_IERC20.sol";

/// @author YLDR <admin@apyflow.com>
library SafeAssetConverter {
    error NotEnoughFunds();

    function safeSwap(IAssetConverter assetConverter, address from, address to, uint256 amount)
        internal
        returns (uint256)
    {
        if (amount > IERC20(from).balanceOf(address(this))) {
            revert NotEnoughFunds();
        }
        if (from == to) return amount;
        if (amount == 0) return 0;
        return assetConverter.swap(from, to, amount);
    }

    function previewSafeSwap(IAssetConverter assetConverter, address from, address to, uint256 amount)
        internal
        returns (uint256)
    {
        if (from == to) return amount;
        if (amount == 0) return 0;
        return assetConverter.previewSwap(from, to, amount);
    }
}

