// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";

interface IWrapped is IERC20Upgradeable {
    function deposit() external payable;

    function withdraw(uint wad) external;
}

