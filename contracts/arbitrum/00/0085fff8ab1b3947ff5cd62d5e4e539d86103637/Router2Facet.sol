// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AppStorage} from "./LibMagpieRouter.sol";
import {IRouter2} from "./IRouter2.sol";
import {Hop} from "./LibHop.sol";
import {LibCurveLp} from "./LibCurveLp.sol";

contract Router2Facet is IRouter2 {
    AppStorage internal s;

    function swapCurveLp(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibCurveLp.swapCurveLp(h);
    }
}

