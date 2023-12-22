// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IReferralStorage {
    function codeOwners(bytes32 _code) external view returns (address);
    function getReferralInfo(address _account) external view returns (bytes32, address);
    function getOwnedCodes(address _account) external view returns (bytes32[] memory);
    function setReferralCodeByUser(bytes32 _code) external;
}

