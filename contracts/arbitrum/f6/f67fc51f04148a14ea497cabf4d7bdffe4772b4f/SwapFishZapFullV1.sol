// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import "./SwapFishZap.sol";
import "./ISwapFishRouter02.sol";

contract SwapFishZapFullV1 is SwapFishZap
{
    constructor(ISwapFishRouter02 _router)
        SwapFishZap(_router)
    {}
}
