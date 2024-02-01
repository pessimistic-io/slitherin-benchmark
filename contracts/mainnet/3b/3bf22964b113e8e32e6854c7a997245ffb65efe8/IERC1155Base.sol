// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC1155} from "./IERC1155.sol";

/**
 * @title ERC1155 base interface
 */
interface IERC1155Base is IERC1155 {
    event UpdatedTokenPrice(
        uint256 tokenId,
        uint256 oldPrice,
        uint256 newPrice
    );

    event UpdatedTokenPercentage(
        uint256 tokenId,
        uint8 oldPercentage,
        uint8 percentage
    );
}

