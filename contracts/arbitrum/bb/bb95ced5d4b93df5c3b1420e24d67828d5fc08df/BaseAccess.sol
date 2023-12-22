// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./Ownable.sol";

contract BaseAccess is Ownable {
    mapping(address => bool) public hasAccess;

    event GrantAccess(address indexed account, bool hasAccess);

    modifier limitAccess {
        require(hasAccess[msg.sender], "A:FBD");
        _;
    }

    function grantAccess(address _account, bool _hasAccess) onlyOwner external {
        hasAccess[_account] = _hasAccess;
        emit GrantAccess(_account, _hasAccess);
    }
}
