// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import { ISolidStateERC20 } from "./ISolidStateERC20.sol";
import { ERC20Base } from "./ERC20Base.sol";
import { ERC20Extended } from "./ERC20Extended.sol";
import { ERC20Metadata } from "./ERC20Metadata.sol";
import { ERC20Permit } from "./ERC20Permit.sol";

/**
 * @title SolidState ERC20 implementation, including recommended extensions
 */
abstract contract SolidStateERC20 is
    ISolidStateERC20,
    ERC20Base,
    ERC20Extended,
    ERC20Metadata,
    ERC20Permit
{

}

