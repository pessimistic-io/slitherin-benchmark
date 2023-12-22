// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEarningsReferral {
    function recordReferral(address _user, address _referrer) external;

    function recordReferralCommission(
        address _referrer,
        uint256 _commission
    ) external;

    function getReferrer(address _user) external view returns (address);
}

