//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

interface ISwap {
    function swap(IERC20 _fromToken, uint256 _amount)
        external
        returns (uint256);
}

