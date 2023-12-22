// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import { ISafeOwnable } from "./ISafeOwnable.sol";
import { IERC165 } from "./IERC165.sol";
import { IDiamondBase } from "./IDiamondBase.sol";
import { IDiamondFallback } from "./IDiamondFallback.sol";
import { IDiamondReadable } from "./IDiamondReadable.sol";
import { IDiamondWritable } from "./IDiamondWritable.sol";

interface ISolidStateDiamond is
    IDiamondBase,
    IDiamondFallback,
    IDiamondReadable,
    IDiamondWritable,
    ISafeOwnable,
    IERC165
{
    receive() external payable;
}

