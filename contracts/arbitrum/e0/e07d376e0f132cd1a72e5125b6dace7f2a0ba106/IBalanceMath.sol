// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./MathStructures.sol";

interface IBalanceMath {

    function liquidityToActions(CalcContextRequest memory request) external view returns (Action[] memory, Deltas memory);

}



