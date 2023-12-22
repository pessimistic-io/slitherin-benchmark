// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AppStorage, LibMagpieRouter} from "./LibMagpieRouter.sol";
import {LibAsset} from "./LibAsset.sol";

struct Hop {
    address addr;
    uint256 amountIn;
    address recipient;
    bytes[] poolDataList;
    address[] path;
}

struct HopParams {
    uint16 ammId;
    uint256 amountIn;
    bytes[] poolDataList;
    address[] path;
}

