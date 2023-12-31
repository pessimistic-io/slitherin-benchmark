// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IVPoolWrapper } from "./IVPoolWrapper.sol";
import { IClearingHouse } from "./IClearingHouse.sol";

interface ISwapSimulator {
    function simulateSwapView(
        IClearingHouse clearingHouse,
        uint32 poolId,
        int256 amount,
        uint160 sqrtPriceLimitX96,
        bool isNotional
    ) external view returns (IVPoolWrapper.SwapResult memory swapResult);
}

