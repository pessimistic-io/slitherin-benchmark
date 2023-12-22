// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./Intervals.sol";
import "./APR.sol";

library ComputeReward {

    function calc(
        uint256 _balance,
        uint256 _apr,
        uint256 _interval
    ) internal pure returns (uint256) {
        return
            _balance * APR.dailyApr(_apr) * _interval / 1 days / 10000 / 100;
    }

}

