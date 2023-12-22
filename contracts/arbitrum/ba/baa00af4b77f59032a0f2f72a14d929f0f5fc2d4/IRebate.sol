
// SPDX-License-Identifier: MIT LICENSE 

pragma solidity ^0.8.0;

interface IRebate {
    function isValidReferrer(address _referrer) external view returns(bool);
    function rebateTo(address _referrer, address _token, uint256 _amount) external returns(uint256);
}
