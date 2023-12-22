// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IDarkAgeRealm {
    function conflagrateVictim(address _peasant, uint256 _amount) external;
    function departSanctuary(uint256 _amount) external;
    function claimTreasure() external;
    function getClaimableTreasure(address _peasant) external view returns (uint256);
    function onTokenTransfer(address sender, uint256 value, bytes calldata _data) external;
    function isPaused() external view returns (bool);
}

