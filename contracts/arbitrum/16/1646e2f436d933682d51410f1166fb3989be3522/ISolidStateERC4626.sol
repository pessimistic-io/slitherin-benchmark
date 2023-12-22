// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import { ISolidStateERC20 } from "./ISolidStateERC20.sol";
import { IERC4626Base } from "./IERC4626Base.sol";

interface ISolidStateERC4626 is IERC4626Base, ISolidStateERC20 {}

