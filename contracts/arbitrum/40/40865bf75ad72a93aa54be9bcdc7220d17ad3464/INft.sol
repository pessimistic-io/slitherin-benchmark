// SPDX-License-Identifier: MIT
import "./IERC721.sol";

pragma solidity 0.8.10;

interface INft is IERC721 {
    function mint(address to, uint256 tokenId) external;

    function mint(address to) external returns (uint256);

    function burn(uint256 tokenId) external;
}

