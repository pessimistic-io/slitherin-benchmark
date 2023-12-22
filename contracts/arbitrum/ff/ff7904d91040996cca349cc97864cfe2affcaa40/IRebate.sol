
// SPDX-License-Identifier: MIT LICENSE 

pragma solidity ^0.6.12;

interface IRebate {
    function isValidReferrer(address _referrer) external view returns(bool);
    function rebateTo(address _referrer, address _token, uint256 _amount) external returns(uint256);
    function getReferrer(address _addr) external view returns(address[2] memory);
}
