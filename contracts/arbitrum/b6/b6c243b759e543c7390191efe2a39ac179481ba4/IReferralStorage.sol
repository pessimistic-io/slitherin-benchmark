// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IReferralStorage {
    function codeOwners(bytes32 _code) external view returns (address);
    function userReferralCodes(address _account) external view returns (bytes32);
    function getUserReferralInfo(address _account) external view returns (bytes32, address);
    function setUserReferralCode(address _account, bytes32 _code) external;
    function setCodeOwnerAdmin(bytes32 _code, address _newAccount) external;
    function setCommission(uint256 _commission) external;
    function getReferrer(address _account) external view returns (address);
}
