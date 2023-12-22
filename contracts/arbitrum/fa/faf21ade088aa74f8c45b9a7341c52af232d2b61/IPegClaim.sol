//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPegClaim {
    function claimPeg() external;

    function enablePegClaim() external;

    function claimEnabled() external view returns (bool);

    function userPegClaimed(address _user) external view returns (bool);

    function userBlacklisted(address _user) external view returns (bool);

    function calculatePegOwed(address _user) external view returns (uint256);

    function totalPegClaimable() external view returns (uint256);

    function setBlacklistAddress(address _user) external;

    function removeBlacklistAddress(address _user) external;
}

