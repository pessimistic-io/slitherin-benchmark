// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./PoolsharkStructs.sol";

interface IRangeStaker is PoolsharkStructs {
    function stakeRange(StakeRangeParams memory) external;
}

