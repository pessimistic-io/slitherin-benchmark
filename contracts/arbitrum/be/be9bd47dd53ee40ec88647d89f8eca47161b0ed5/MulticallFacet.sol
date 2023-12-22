// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LibDiamond} from "./LibDiamond.sol";
import {AppStorage} from "./LibMagpieAggregator.sol";
import {LibMulticall} from "./LibMulticall.sol";
import {IMulticall} from "./IMulticall.sol";

contract MulticallFacet is IMulticall {
    AppStorage internal s;

    function multicall(bytes4[] calldata selectors, bytes[] calldata data) external {
        LibDiamond.enforceIsContractOwner();
        LibMulticall.multicall(selectors, data);
    }
}

