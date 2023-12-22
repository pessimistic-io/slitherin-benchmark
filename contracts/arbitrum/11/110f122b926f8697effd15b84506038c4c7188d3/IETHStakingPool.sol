// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import { IAmm } from "./IAmm.sol";
import { IERC20 } from "./IERC20.sol";

interface IETHStakingPool {
    // overriden by storage var
    function totalSupply() external view returns (uint256);

    // overriden by storage var
    function quoteToken() external view returns (IERC20);

    function calculateTotalReward() external view returns (int256);

    function withdraw(IAmm _amm, uint256 _amount) external;
}

