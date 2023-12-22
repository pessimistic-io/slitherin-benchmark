// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILandDistributor  {
    function issueLand(address _recipient, uint256 _amount) external;
}

