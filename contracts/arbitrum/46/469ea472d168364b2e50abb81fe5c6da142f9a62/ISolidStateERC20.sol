// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import { IERC20Base } from "./IERC20Base.sol";
import { IERC20Extended } from "./IERC20Extended.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { IERC20Permit } from "./IERC20Permit.sol";

interface ISolidStateERC20 is
    IERC20Base,
    IERC20Extended,
    IERC20Metadata,
    IERC20Permit
{}

