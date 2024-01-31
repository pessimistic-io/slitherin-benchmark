// SPDX-License-Identifier: BUSDL-1.1
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import {IERC20} from "./IERC20.sol";
import {IAssetAllocation} from "./common_Imports.sol";
import {ConvexMimConstants} from "./metapool_Constants.sol";
import {     MetaPoolDepositorZap } from "./metapool_Imports.sol";

contract ConvexMimZap is MetaPoolDepositorZap, ConvexMimConstants {
    constructor()
        public
        MetaPoolDepositorZap(META_POOL, address(LP_TOKEN), PID, 10000, 100) // solhint-disable-next-line no-empty-blocks
    {}

    function assetAllocations() public view override returns (string[] memory) {
        string[] memory allocationNames = new string[](2);
        allocationNames[0] = "curve-mim";
        allocationNames[1] = NAME;
        return allocationNames;
    }

    function erc20Allocations() public view override returns (IERC20[] memory) {
        IERC20[] memory allocations = _createErc20AllocationArray(1);
        allocations[4] = PRIMARY_UNDERLYER;
        return allocations;
    }
}

