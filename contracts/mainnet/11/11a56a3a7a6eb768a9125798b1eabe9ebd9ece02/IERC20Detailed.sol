// SPDX-License-Identifier: MIT

// uniswap Library only works under 0.7.6
pragma solidity =0.7.6;

import {IERC20} from "./IERC20.sol";

interface IERC20Detailed is IERC20 {
    function decimals() external view returns (uint8);
}

