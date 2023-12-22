// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IReferralHub {
    function addReferral(
        uint256 _tokenId,
        uint256 _referredUserId
    ) external returns (uint256);

    function claimReferral(
        uint256 _tokenId,
        address _to
    ) external returns (uint256);

    function getReferral(uint256 _tokenId) external view returns (uint256);

    function getReferredUsers(
        uint256 _tokenId
    ) external view returns (uint256[] memory);
}

