// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import { LendgineAddress } from "./LendgineAddress.sol";
import { ILendgine } from "./ILendgine.sol";

/// @notice Provides validation for callbacks from Numoen Lendgines
/// @author Kyle Scott (https://github.com/Numoen/manager/blob/master/src/libraries/CallbackValidation.sol)
/// @author Modified from Uniswap
/// (https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/PoolAddress.sol)
library CallbackValidation {
    error VerifyError();

    function verifyCallback(address factory, LendgineAddress.LendgineKey memory lendgineKey)
        internal
        view
        returns (ILendgine lendgine)
    {
        lendgine = ILendgine(
            LendgineAddress.computeLendgineAddress(
                factory,
                lendgineKey.base,
                lendgineKey.speculative,
                lendgineKey.baseScaleFactor,
                lendgineKey.speculativeScaleFactor,
                lendgineKey.upperBound
            )
        );
        if (msg.sender != address(lendgine)) revert VerifyError();
    }
}

