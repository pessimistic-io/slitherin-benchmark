// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./IModuleManager.sol";
import "./IModuleRegistry.sol";
import "./Address.sol";

contract ModuleManager is Ownable, IModuleManager {
    using Address for address;

    bool internal _isInitialized;
    IModuleRegistry internal immutable _registry;

    mapping(address => bool) internal _modules;
    mapping(bytes4 => address) internal _delegates;

    constructor(address registry) {
        require(
            registry.isContract(),
            "MM: registry must be an existing contract address"
        );

        _isInitialized = true;
        _registry = IModuleRegistry(registry);
    }

    function initialize(address initialOwner) external {
        require(!_isInitialized, "MM: contract is already initialized");

        _isInitialized = true;

        _setOwner(initialOwner);
    }

    function isModuleEnabled(address module)
        external
        view
        override
        returns (bool)
    {
        return _modules[module];
    }

    function enableModule(address module) external override onlyOwner {
        require(!_modules[module], "MM: module is already enabled");
        require(
            _registry.isModuleRegistered(module),
            "MM: module must be registered"
        );

        _modules[module] = true;

        emit ModuleEnabled(module);
    }

    function disableModule(address module) external override onlyOwner {
        require(_modules[module], "MM: module is already disabled");

        delete _modules[module];

        emit ModuleDisabled(module);
    }

    function getDelegate(bytes4 methodID)
        external
        view
        override
        returns (address)
    {
        return _delegates[methodID];
    }

    function enableDelegation(bytes4 methodID, address module)
        external
        override
        onlyOwner
    {
        require(
            _delegates[methodID] != module,
            "MM: delegation is already enabled"
        );
        require(_modules[module], "MM: module must be enabled");

        _delegates[methodID] = module;

        emit DelegationEnabled(methodID, module);
    }

    function disableDelegation(bytes4 methodID) external override onlyOwner {
        require(
            _delegates[methodID] != address(0),
            "MM: delegation is already disabled"
        );

        delete _delegates[methodID];

        emit DelegationDisabled(methodID);
    }
}

