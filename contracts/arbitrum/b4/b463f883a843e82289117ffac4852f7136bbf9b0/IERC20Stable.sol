// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20.sol";
import "./draft-IERC20Permit.sol";

interface IERC20Stable is IERC20, IERC20Permit {}

