// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import "./interfaces_IERC20.sol";

interface WETH9 is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

