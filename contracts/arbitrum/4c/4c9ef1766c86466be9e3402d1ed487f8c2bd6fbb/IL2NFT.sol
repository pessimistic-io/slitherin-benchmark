//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IERC721Enumerable.sol";

interface IL2NFT is IERC721Enumerable {
    function mint(address to) external;
    function adminMint(address to) external;
}

