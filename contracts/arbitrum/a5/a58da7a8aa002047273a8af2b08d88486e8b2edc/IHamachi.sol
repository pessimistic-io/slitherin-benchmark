// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20Upgradeable} from "./ERC20_IERC20Upgradeable.sol";

interface IHamachi is IERC20Upgradeable {
    function updateRewardBalance(address account, int256 difference) external;
}

