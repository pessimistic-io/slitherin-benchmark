// SPDX-License-Identifier: MIT
// author : zainamroti
pragma solidity ^0.8.7;

interface IBrokerDefiPro  {
    function proCodesVerification(uint256) external view returns(bool);
    function codeOwners(uint256) external view returns(uint256);
    function ownerOf(uint256 tokenId) external returns (address);
}
