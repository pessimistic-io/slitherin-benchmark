// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IAccountGroup {
    event DefaultInitializerUpdated(address indexed initializer);
    event SubgroupInitializerUpdated(uint64 indexed subgroupId, address indexed initializer);
    event DefaultAccountImplementationUpdated(address indexed implementation);

    error UpgradeRestricted(address sender, address account, address implementation);

    function initialize(address owner) external;
    function getDefaultAccountInitializer() external view returns (address);
    function setDefaultAccountInitializer(address initializer) external;
    function setAccountInitializer(uint64 subgroupId, address initializer) external;
    function getDefaultAccountImplementation() external view returns (address);
    function setDefaultAccountImplementation(address implementation) external;
}

