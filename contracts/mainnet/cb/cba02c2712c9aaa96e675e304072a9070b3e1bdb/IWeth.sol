// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";

interface IWeth is IERC20Upgradeable {
    function deposit() external payable;

    function withdraw(uint256) external;
}

