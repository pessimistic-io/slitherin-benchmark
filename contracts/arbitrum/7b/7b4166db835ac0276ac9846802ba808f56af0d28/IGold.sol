// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces_IERC20.sol";

interface IGold is IERC20 {
    function mint(address to, uint256 amount) external;
}
