// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

contract ThirdPartyExecutionSyntheticId {
    // Mapping containing whether msg.sender allowed his positions to be executed by third party
    mapping (address => bool) internal isThirdPartyExecutionAllowed;

    function _allowThirdpartyExecution(address _user, bool _allow) internal {
        isThirdPartyExecutionAllowed[_user] = _allow;
    }
}

