// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IReferrals {
    function setReferred(address _referredTrader, address _referrer) external;
    function getReferred(address _trader) external view returns (address, uint);
    function addRefFees(address _trader, address _tigAsset, uint _fees) external;
}
