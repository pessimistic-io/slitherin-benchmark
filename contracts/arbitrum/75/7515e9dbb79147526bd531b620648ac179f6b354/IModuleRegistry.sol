// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

interface IModuleRegistry {
    event ModuleRegistered(address indexed module);

    event ModuleDeregistered(address indexed module);

    function isModuleRegistered(address module) external view returns (bool);

    function registerModule(address module) external;

    function deregisterModule(address module) external;
}

