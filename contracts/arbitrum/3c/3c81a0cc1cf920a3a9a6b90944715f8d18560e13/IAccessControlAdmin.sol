// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IAccessControlAdmin {
    function grantAdminRole(address admin) external;

    function grantSignerRole(address signer) external;
}

