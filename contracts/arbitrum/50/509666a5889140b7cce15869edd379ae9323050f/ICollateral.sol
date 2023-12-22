// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import "./IERC20.sol";

interface ICollateral is IERC20 {
    function mint(address to, uint256 amount) external;
}

