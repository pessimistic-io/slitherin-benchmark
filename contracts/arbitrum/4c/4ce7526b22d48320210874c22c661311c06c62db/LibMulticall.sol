// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {LibDiamond} from "./LibDiamond.sol";

error SelectorsLengthInvalid();
error InvalidMulticall();

library LibMulticall {
    function multicall(bytes4[] calldata selectors, bytes[] calldata data) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        if (selectors.length != data.length) {
            revert SelectorsLengthInvalid();
        }

        for (uint256 i = 0; i < data.length; i++) {
            address facet = ds.selectorToFacetAndPosition[selectors[i]].facetAddress;
            (bool success, ) = address(facet).delegatecall(data[i]);
            if (!success) {
                revert InvalidMulticall();
            }
        }
    }
}

