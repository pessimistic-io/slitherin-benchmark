//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import {IERC721Enumerable} from "./IERC721Enumerable.sol";

interface IPositionMinter is IERC721Enumerable {
    function mint(address to) external returns (uint256 tokenId);

    function burnToken(uint256 tokenId) external;
}

