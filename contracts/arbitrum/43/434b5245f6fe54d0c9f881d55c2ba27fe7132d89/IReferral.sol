// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.6.12;

interface IReferral {
    function setReferral(address userAccount, address referralAccount) external;

    function getReferral(address userAccount) external view returns (address);
}

