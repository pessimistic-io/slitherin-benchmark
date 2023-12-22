//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IERC20} from "./IERC20.sol";

interface IERC20Decimals is IERC20 {
    function decimals() external view returns (uint8);
}

