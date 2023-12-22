// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPermissionsFacet {
    struct Storage {
        bool initialized;
        mapping(address => mapping(address => uint256)) userContractRoles;
        mapping(bytes4 => uint256) signatureRoles;
        mapping(address => mapping(bytes4 => bool)) isEveryoneAllowedToCall;
    }

    function initializePermissionsFacet(address admin) external;

    function hasPermission(address user, address contractAddress, bytes4 signature) external view returns (bool);

    function requirePermission(address user, address contractAddress, bytes4 signature) external;

    function setGeneralRole(address contractAddress, bytes4 signature, bool value) external;

    function grantUserContractRole(uint8 role, address user, address contractAddress) external;

    function revokeUserContractRole(uint8 role, address user, address contractAddress) external;

    function grantSignatureRole(uint8 role, bytes4 signature) external;

    function revokeSignatureRole(uint8 role, bytes4 signature) external;
}

