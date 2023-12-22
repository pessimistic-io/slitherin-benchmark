// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./IERC20.sol";

interface IMCB is IERC20 {
    function tokenSupplyOnL1() external view returns (uint256);
}

