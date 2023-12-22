// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./IERC721.sol";
import { BasicCollectionParams } from "./ERC721Structs.sol";

interface IOmniseaRemoteERC721 is IERC721 {
    function initialize(BasicCollectionParams memory _collectionParams) external;
    function mint(address owner, uint256 tokenId) external;
    function exists(uint256 tokenId) external view returns (bool);
}

