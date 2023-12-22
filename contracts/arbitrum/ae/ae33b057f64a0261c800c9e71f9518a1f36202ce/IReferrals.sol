// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IReferrals {

    function setReferred(address _referredTrader, address _referrer) external;
    function getReferred(address _trader) external view returns (address);

}
