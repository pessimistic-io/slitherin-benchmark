// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721Enumerable.sol";

interface ICitizen is IERC721Enumerable {
    function mintCollectible(uint256 numTokens) external payable;
}
