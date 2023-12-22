// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMGPBurnEventManager {
    function joinEventFor(address _user, uint256 _eventId, uint256 _mgpBurnAmount) external;
}
