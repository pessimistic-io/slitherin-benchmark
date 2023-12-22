// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Hop} from "./LibHop.sol";

interface IRouter2 {
    function swapCurveLp(Hop calldata h) external payable returns (uint256 amountOut);
}

