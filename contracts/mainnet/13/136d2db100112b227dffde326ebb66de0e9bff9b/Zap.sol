// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import {IERC20} from "./IERC20.sol";
import {IAssetAllocation} from "./common_Imports.sol";
import {ConvexBusdv2Constants} from "./metapool_Constants.sol";
import {     MetaPoolDepositorZapV2 } from "./metapool_Imports.sol";

contract ConvexBusdv2Zap is MetaPoolDepositorZapV2, ConvexBusdv2Constants {
    constructor()
        public
        MetaPoolDepositorZapV2(META_POOL, address(LP_TOKEN), PID, 10000, 100) // solhint-disable-next-line no-empty-blocks
    {}

    function assetAllocations() public view override returns (string[] memory) {
        string[] memory allocationNames = new string[](1);
        allocationNames[0] = NAME;
        return allocationNames;
    }

    function erc20Allocations() public view override returns (IERC20[] memory) {
        IERC20[] memory allocations = _createErc20AllocationArray(0);
        return allocations;
    }
}

