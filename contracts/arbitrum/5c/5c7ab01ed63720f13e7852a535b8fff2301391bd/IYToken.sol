// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IERC20.sol";

interface IYToken is IERC20 {
    function burn(uint256 _amount) external;
}

