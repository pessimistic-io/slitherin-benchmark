// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IBaseStrategy.sol";

interface ITokenStrategy is IBaseStrategy {
    function deposit() external;
}


