// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IERC20 } from "./IERC20.sol";

interface IAaveToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

