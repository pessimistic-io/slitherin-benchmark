// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./IERC721.sol";

interface ICaptainz {
    function isPotatozQuesting(uint256 tokenId) external view returns (bool);
}
