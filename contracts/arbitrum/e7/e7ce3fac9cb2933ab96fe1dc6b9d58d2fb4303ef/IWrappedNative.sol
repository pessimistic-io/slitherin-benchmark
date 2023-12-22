// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20} from "./IERC20Metadata.sol";

interface IWrappedNative is IERC20 {
    function deposit() external payable;
}

