// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import { IERC1155Base } from "./IERC1155Base.sol";
import { IERC1155Enumerable } from "./IERC1155Enumerable.sol";
import { IERC1155Metadata } from "./IERC1155Metadata.sol";

interface ISolidStateERC1155 is
    IERC1155Base,
    IERC1155Enumerable,
    IERC1155Metadata
{}

