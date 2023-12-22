//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IERC721MintableBurnable{
    function burn(uint tokenId) external;
    function mint(address to, uint tokenId) external;
}
