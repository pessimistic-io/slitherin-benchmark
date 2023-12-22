// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

interface IModuleManager {
    event ModuleEnabled(address indexed module);

    event ModuleDisabled(address indexed module);

    event DelegationEnabled(bytes4 indexed methodID, address indexed module);

    event DelegationDisabled(bytes4 indexed methodID);

    function initialize(address initialOwner) external;

    function isModuleEnabled(address module) external view returns (bool);

    function enableModule(address module) external;

    function disableModule(address module) external;

    function getDelegate(bytes4 methodID) external view returns (address);

    function enableDelegation(bytes4 methodID, address module) external;

    function disableDelegation(bytes4 methodID) external;
}

