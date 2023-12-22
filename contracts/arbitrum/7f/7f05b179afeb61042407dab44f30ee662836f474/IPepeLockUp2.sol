//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPepeLockUp } from "./IPepeLockUp.sol";

interface IPepeLockUp2 is IPepeLockUp {
    function accumulatedUsdcPerLpShare() external view returns (uint256);

    function totalLpShares() external view returns (uint256);
}

