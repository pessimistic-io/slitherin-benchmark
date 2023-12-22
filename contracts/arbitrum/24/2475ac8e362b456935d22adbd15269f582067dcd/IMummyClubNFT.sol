// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;


import "./IERC721.sol";
import "./ERC721Enumerable.sol";

interface IMummyClubNFT is IERC721, IERC721Enumerable {

    function getTokenPower(uint256 tokenId) external view returns (uint256);

}

