// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC1155Base} from "./IERC1155Base.sol";
import {IERC1155Enumerable} from "./IERC1155Enumerable.sol";

interface IKomonERC1155 is IERC1155Base, IERC1155Enumerable {
    event CreatedSpaceToken(
        uint256 newTokenId,
        uint256 maxSupply,
        uint256 initialPrice,
        uint8 percentage,
        address creatorAccount
    );

    event InternalKomonKeysMinted(
        address sender,
        uint256 newTokenId,
        uint256 amount
    );
}

