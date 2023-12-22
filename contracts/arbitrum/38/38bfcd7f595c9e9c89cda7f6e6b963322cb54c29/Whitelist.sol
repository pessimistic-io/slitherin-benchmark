//SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./Ownable2Step.sol";

contract Whitelist is Ownable2Step {
    mapping(address => bool) public isWhitelisted;

    function updateWhitelist(
        address _address,
        bool _isActive
    ) external onlyOwner {
        isWhitelisted[_address] = _isActive;
    }

    function getWhitelisted(address _address) external view returns (bool) {
        return isWhitelisted[_address];
    }
}

