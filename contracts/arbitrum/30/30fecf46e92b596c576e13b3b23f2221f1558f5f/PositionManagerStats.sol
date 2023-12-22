// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TokenExposure} from "./TokenExposure.sol";
import {TokenAllocation} from "./TokenAllocation.sol";

struct PositionManagerStats {
    address positionManagerAddress;
    uint256 positionWorth;
    uint256 costBasis;
    int256 pnl;
    TokenExposure[] tokenExposures;
    TokenAllocation[] tokenAllocation;
    bool canRebalance;
}
