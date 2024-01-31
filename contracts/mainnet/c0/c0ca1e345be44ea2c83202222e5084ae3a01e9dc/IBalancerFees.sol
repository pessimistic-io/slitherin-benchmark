// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

interface IBalancerFees {
    function getSwapFeePercentage() external view returns (uint256);
}

