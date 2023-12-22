// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IReferralStorage {
    function setReferralCode(address _account, bytes32 _code) external;
}

