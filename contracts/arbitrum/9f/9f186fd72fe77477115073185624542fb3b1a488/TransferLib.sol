//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./SafeERC20Upgradeable.sol";

library TransferLib {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    error ZeroAddress(address payer, address to);

    function transferOut(IERC20Upgradeable token, address payer, address to, uint256 amount)
        internal
        returns (uint256)
    {
        if (payer == address(0) || to == address(0)) {
            revert ZeroAddress(payer, to);
        }

        // If we are the payer, it's because the funds where transferred first or it was WETH wrapping
        if (payer == address(this)) {
            token.safeTransfer(to, amount);
        } else {
            token.safeTransferFrom(payer, to, amount);
        }

        return amount;
    }
}

