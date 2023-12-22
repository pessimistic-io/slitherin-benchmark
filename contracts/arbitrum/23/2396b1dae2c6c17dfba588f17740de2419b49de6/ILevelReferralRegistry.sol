// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface ILevelReferralRegistry {
    function referredBy(address) external view returns (address);

    function setReferrer(address _trader, address _referrer) external;
}

