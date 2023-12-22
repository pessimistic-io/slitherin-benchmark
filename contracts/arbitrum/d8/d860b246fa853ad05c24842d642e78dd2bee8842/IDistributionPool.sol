// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IDistributionPool {
    function _claimedUser(address _user) external view returns(bool);
}
