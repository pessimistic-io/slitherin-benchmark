// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IAccessControlAdmin {
    function grantAdminRole(address admin) external;

    function grantPauserRole(address pauser) external;

    function grantRevenueRole(address collector) external;

    function grantEmergencyRole(address emergency) external;
}

