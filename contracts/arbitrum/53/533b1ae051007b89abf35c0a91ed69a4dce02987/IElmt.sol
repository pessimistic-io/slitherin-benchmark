
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IERC20.sol";

interface IElmt is IERC20 {
    function burnFrom(address account, uint256 amount) external;
}
