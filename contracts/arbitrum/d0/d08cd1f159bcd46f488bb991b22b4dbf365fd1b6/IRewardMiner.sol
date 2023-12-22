// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

interface IRewardMiner {
    function mint(address trader, uint256 amount, int256 pnl) external;

}

