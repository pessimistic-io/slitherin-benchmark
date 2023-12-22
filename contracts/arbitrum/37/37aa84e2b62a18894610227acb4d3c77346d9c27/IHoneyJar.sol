// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC721} from "./IERC721.sol";

interface IHoneyJar is IERC721 {
    function mintOne(address to) external returns (uint256);

    function mintTokenId(address to, uint256 tokenId) external;

    function batchMint(address to, uint256 amount) external;

    function burn(uint256 _id) external;

    function nextTokenId() external view returns (uint256);
}

