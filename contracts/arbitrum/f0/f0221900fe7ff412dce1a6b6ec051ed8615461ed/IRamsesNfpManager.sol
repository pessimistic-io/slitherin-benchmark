// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

interface IRamsesNfpManager {
    function balanceOf(address) external view returns (uint256);
    function tokenOfOwnerByIndex(address, uint256) external view returns (uint256);
    function positions(uint256) external view returns (uint96,address,address,address,uint24,int24,int24,uint128,uint256,uint256,uint128,uint128);
    function ownerOf(uint256) external view returns (address);
}
