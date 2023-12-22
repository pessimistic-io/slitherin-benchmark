// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "./IFactory.sol";
import "./IPayoffProvider.sol";

interface IPayoffFactory is IFactory {
    function initialize() external;
}

