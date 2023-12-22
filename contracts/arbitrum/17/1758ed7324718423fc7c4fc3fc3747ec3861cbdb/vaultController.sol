// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IErrors} from "./IErrors.sol";
import {IEarthquake} from "./IEarthquake.sol";

abstract contract VaultController is IErrors {
    using SafeTransferLib for ERC20;

    function _depositToVault(
        uint256 id,
        uint256 amount,
        address receiver,
        address inputToken,
        address vaultAddress
    ) internal {
        if (msg.value > 0) {
            IEarthquake(vaultAddress).depositETH{value: address(this).balance}(
                id,
                receiver
            );
        } else {
            ERC20(inputToken).safeApprove(address(vaultAddress), amount);
            IEarthquake(vaultAddress).deposit(id, amount, receiver);
        }
    }

    function _withdrawFromVault(
        uint256 id,
        uint256 assets,
        address receiver,
        address vaultAddress
    ) internal returns (uint256) {
        return
            IEarthquake(vaultAddress).withdraw(
                id,
                assets,
                receiver,
                address(this)
            );
    }
}

