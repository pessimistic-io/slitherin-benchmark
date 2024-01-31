// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IENERGY is IERC20 {
    function mint(uint256 amount) external;

    function startDripping(address addr, uint128 multiplier) external;

    function stopDripping(address addr, uint128 multiplier) external;

    function burn(address from, uint256 value) external;

    function burnSystem(address from, uint256 value) external;
}
