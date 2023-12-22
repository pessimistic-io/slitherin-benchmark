// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import "./console.sol";

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";


interface IStakingPool {
    function injectRewards(uint256 _amount) external;
}

