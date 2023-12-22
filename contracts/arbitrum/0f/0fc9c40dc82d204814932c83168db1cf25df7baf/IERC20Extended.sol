// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);
}

