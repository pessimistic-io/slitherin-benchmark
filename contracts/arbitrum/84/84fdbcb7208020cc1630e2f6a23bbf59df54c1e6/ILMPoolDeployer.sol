// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IOreoV3Pool.sol";
import "./ILMPool.sol";

interface ILMPoolDeployer {
    function deploy(IOreoV3Pool pool) external returns (ILMPool lmPool);
}

