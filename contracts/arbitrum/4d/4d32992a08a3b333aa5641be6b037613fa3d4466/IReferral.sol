// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

interface IReferral {
    function setReferral(address userAccount, address referralAccount) external;

    function getReferral(address userAccount) external view returns (address);
}

