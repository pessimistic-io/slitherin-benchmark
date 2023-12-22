// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";

interface IGovToken is IERC20 {
    function mint(address, uint256) external;
}
