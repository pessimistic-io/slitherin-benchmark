// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

interface IIdentity {
    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );

    event ModuleManagerSwitched(
        address indexed oldModuleManager,
        address indexed newModuleManager
    );

    event Executed(
        address indexed module,
        address indexed to,
        uint256 value,
        bytes data
    );

    function owner() external view returns (address);

    function setOwner(address newOwner) external;

    function moduleManager() external view returns (address);

    function setModuleManager(address newModuleManager) external;

    function isModuleEnabled(address module) external view returns (bool);

    function getDelegate(bytes4 methodID) external view returns (address);

    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bytes memory);
}

