// SPDX-License-Identifier: MIT
// author : zainamroti
pragma solidity ^0.8.7;

interface IBrokerDefiPartner  {
    function partnerCodesVerification(uint256) external view returns(bool);
    function codeOwners(uint256) external view returns(uint256);
    function ownerOf(uint256 tokenId) external returns (address);
}
