// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBAYCSewerPassClaim {
    function claimBaycBakc(uint256 baycTokenId, uint256 bakcTokenId) external;
    function claimBayc(uint256 baycTokenId) external;
    function claimMaycBakc(uint256 maycTokenId, uint256 bakcTokenId) external;
    function claimMayc(uint256 maycTokenId) external;
    function checkClaimed(uint8 collectionId, uint256 tokenId) external view returns (bool);
    function bakcClaimed(uint256 doggoId) external view returns (bool);
}
