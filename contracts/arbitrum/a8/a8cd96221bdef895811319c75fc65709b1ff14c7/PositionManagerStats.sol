// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TokenExposure} from "./TokenExposure.sol";
import {TokenAllocation} from "./TokenAllocation.sol";

struct PositionManagerStats {
    address positionManagerAddress;
    string name;
    uint256 positionWorth;
    uint256 costBasis;
    int256 pnl;
    TokenExposure[] tokenExposures;
    TokenAllocation[] tokenAllocations;
    uint256 price;
    bool canRebalance;
    uint256 collateralRatio;
    uint256 loanWorth;
    uint256 liquidationLevel;
    uint256 collateral;
}
