// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

contract DiscountedUserOracleOtherChains is Ownable {
    // Predefined Free Users
    mapping(address => bool) public freeUser;

    function isDiscountedUser(address _user) external view returns (bool) {
        return freeUser[_user];
    }

    // Owner functions
    function setFreeUser(address _user, bool _isFree) external onlyOwner {
        freeUser[_user] = _isFree;
    }
}
