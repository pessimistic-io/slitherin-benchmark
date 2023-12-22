//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable2StepUpgradeable.sol";

contract Whitelist is Ownable2StepUpgradeable {
    mapping(address => bool) public isWhitelisted;

    function updateWhitelist(address _address, bool _isActive) external onlyOwner {
        isWhitelisted[_address] = _isActive;
    }

    function getWhitelisted(address _address) external view returns (bool) {
        return isWhitelisted[_address];
    }
}

