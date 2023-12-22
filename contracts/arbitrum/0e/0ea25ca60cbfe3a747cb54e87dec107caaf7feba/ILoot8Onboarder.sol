// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ILoot8Onboarder {
    
    event EntityOnboarded(string _inviteCode, address _entity);

    function addInviteHash(bytes32[] memory _hashedCode) external;
    function onboard(string memory _inviteCode, bytes memory _creationData) external returns(address _entity);
}
