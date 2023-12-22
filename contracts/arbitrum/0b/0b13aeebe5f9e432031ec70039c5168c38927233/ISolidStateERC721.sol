// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import { IERC721Base } from "./IERC721Base.sol";
import { IERC721Enumerable } from "./IERC721Enumerable.sol";
import { IERC721Metadata } from "./IERC721Metadata.sol";

interface ISolidStateERC721 is IERC721Base, IERC721Enumerable, IERC721Metadata {
    error SolidStateERC721__PayableApproveNotSupported();
    error SolidStateERC721__PayableTransferNotSupported();
}

