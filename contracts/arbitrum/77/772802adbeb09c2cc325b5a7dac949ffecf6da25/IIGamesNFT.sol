// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./IERC721.sol";
import "./IERC721Metadata.sol";
import "./IERC721Enumerable.sol";

interface IIGamesNFT is IERC721, IERC721Metadata, IERC721Enumerable {
    function mint(address to) external;
}
