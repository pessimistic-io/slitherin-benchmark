// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {IERC20} from "./SafeERC20.sol";

interface IAutoRebalancer {

    event Compound(uint256[4] inMax);

    function rescueERC20(IERC20 token, address recipient) external;

    function autoRebalance(uint256[4] calldata outMin) external returns (
        int24 narrowLower, int24 narrowUpper, int24 wideLower, int24 wideUpper
    );

    function compound(uint256[4] calldata inMax) external;
}
