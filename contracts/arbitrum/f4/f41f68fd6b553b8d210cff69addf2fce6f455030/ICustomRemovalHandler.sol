// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICustomRemovalHandler {
    function removalStarted(address _user, uint256 _requestId, bytes calldata _requirementData, bytes calldata _userData) external;
    function removalEnded(address _user, uint256 _requestId, uint256 _randomNumber, bytes calldata _requirementData) external;
}
