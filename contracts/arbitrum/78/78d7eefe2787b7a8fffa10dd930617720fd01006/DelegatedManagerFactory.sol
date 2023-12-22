/*
    Copyright 2022 Set Labs Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

import {Address} from "./Address.sol";

import {AddressArrayUtils} from "./AddressArrayUtils.sol";
import {IController} from "./IController.sol";
import {IJasperVault} from "./IJasperVault.sol";
import {ISetTokenCreator} from "./ISetTokenCreator.sol";

import {DelegatedManager} from "./DelegatedManager.sol";
import {IDelegatedManager} from "./IDelegatedManager.sol";
import {IManagerCore} from "./IManagerCore.sol";

/**
 * @title DelegatedManagerFactory
 * @author Set Protocol
 *
 * Factory smart contract which gives asset managers the ability to:
 * > create a Set Token managed with a DelegatedManager contract
 * > create a DelegatedManager contract for an existing Set Token to migrate to
 * > initialize extensions and modules for SetTokens using the DelegatedManager system
 */
contract DelegatedManagerFactory {
    using AddressArrayUtils for address[];
    using Address for address;

    mapping(address => address) public account2setToken;
    mapping(address => address) public setToken2account;
    mapping(address => uint256) public jasperVaultType;
    mapping(address => bool) public jasperVaultInitial;

    struct CreateInfo {
        uint256 vaultType;
        address masterToken;
        uint256 followFee;
        uint256 maxFollowFee;
        uint256 profitShareFee;
        address[] components;
        int256[] units;
        string name;
        string symbol;
        address owner;
        address methodologist;
        uint256 delay;
        address[] modules;
        address[] adapters;
        address[] operators;
        address[] assets;
        address[] extensions;
    }

    /* ============ Structs ============ */

    struct InitializeParams {
        address deployer;
        address owner;
        address methodologist;
        IDelegatedManager manager;
        bool isPending;
    }

    /* ============ Events ============ */

    /**
     * @dev Emitted on DelegatedManager creation
     * @param _jasperVault             Instance of the JasperVault being created
     * @param _manager              Address of the DelegatedManager
     * @param _deployer             Address of the deployer
     */
    event DelegatedManagerCreated(
        IJasperVault indexed _jasperVault,
        DelegatedManager indexed _manager,
        address _deployer
    );

    /**
     * @dev Emitted on DelegatedManager initialization
     * @param _jasperVault             Instance of the JasperVault being initialized
     * @param _manager              Address of the DelegatedManager owner
     */
    event DelegatedManagerInitialized(
        IJasperVault indexed _jasperVault,
        IDelegatedManager indexed _manager
    );

    /* ============ State Variables ============ */

    // ManagerCore address
    IManagerCore public immutable managerCore;

    // Controller address
    IController public immutable controller;

    // SetTokenFactory address
    ISetTokenCreator public immutable setTokenFactory;

    // Mapping which stores manager creation metadata between creation and initialization steps
    mapping(IJasperVault => InitializeParams) public initializeState;

    /* ============ Constructor ============ */

    /**
     * @dev Sets managerCore and setTokenFactory address.
     * @param _managerCore                      Address of ManagerCore protocol contract
     * @param _controller                       Address of Controller protocol contract
     * @param _setTokenFactory                  Address of SetTokenFactory protocol contract
     */
    constructor(
        IManagerCore _managerCore,
        IController _controller,
        ISetTokenCreator _setTokenFactory
    ) public {
        managerCore = _managerCore;
        controller = _controller;
        setTokenFactory = _setTokenFactory;
    }

    /* ============ External Functions ============ */

    function createSetAndManager(
        CreateInfo memory _info
    ) external returns (IJasperVault, address) {
        // require(account2setToken[msg.sender] == address(0x0000000000000000000000000000000000000000), "sender has a jasperVault");
        require(_info.owner != address(0x00), "owner invalid address");
        require(
            _info.methodologist != address(0x00),
            "methodologist invalid address"
        );
        require(
            _info.profitShareFee <= 10 ** 18,
            "profitShareFee less than or equal to 1e18"
        );
        _validateManagerParameters(
            _info.components,
            _info.extensions,
            _info.assets
        );
        IJasperVault jasperVault = _deploySet(
            _info.components,
            _info.units,
            _info.modules,
            _info.name,
            _info.symbol,
            _info.masterToken,
            _info.followFee,
            _info.maxFollowFee,
            _info.profitShareFee
        );

        DelegatedManager manager = _deployManager(
            jasperVault,
            _info.extensions,
            _info.operators,
            _info.assets,
            _info.adapters,
            _info.delay
        );

        _setInitializationState(
            jasperVault,
            address(manager),
            _info.owner,
            _info.methodologist
        );

        account2setToken[msg.sender] = address(jasperVault);
        setToken2account[address(jasperVault)] = msg.sender;
        jasperVaultType[address(jasperVault)] = _info.vaultType;
        return (jasperVault, address(manager));
    }

    /**
     * ONLY SETTOKEN MANAGER: Deploys a DelegatedManager and sets some temporary metadata about the
     * deployment which will be read during a subsequent intialization step which wires everything together.
     * This method is used when migrating an existing JasperVault to the DelegatedManager system.
     *
     * (Note: This flow should work well for SetTokens managed by an EOA. However, existing
     * contract-managed Sets may need to have their ownership temporarily transferred to an EOA when
     * migrating. We don't anticipate high demand for this migration case though.)
     *
     * @param  _jasperVault         Instance of JasperVault to migrate to the DelegatedManager system
     * @param  _owner            Address to set as the DelegateManager's `owner` role
     * @param  _methodologist    Address to set as the DelegateManager's methodologist role
     * @param  _operators        List of operators authorized for the DelegateManager
     * @param  _assets           List of assets DelegateManager can trade. When empty, asset allow list is not enforced
     * @param  _extensions       List of extensions authorized for the DelegateManager
     *
     * @return (address) Address of the created DelegatedManager
     */
    function createManager(
        IJasperVault _jasperVault,
        address _owner,
        address _methodologist,
        address[] memory _adapters,
        address[] memory _operators,
        address[] memory _assets,
        address[] memory _extensions,
        uint256 _delay
    ) external returns (address) {
        require(
            controller.isSet(address(_jasperVault)),
            "Must be controller-enabled JasperVault"
        );
        require(msg.sender == _jasperVault.manager(), "Must be manager");
        require(_owner != address(0x00), "owner invalid address");
        _validateManagerParameters(
            _jasperVault.getComponents(),
            _extensions,
            _assets
        );

        DelegatedManager manager = _deployManager(
            _jasperVault,
            _extensions,
            _operators,
            _assets,
            _adapters,
            _delay
        );
        _setInitializationState(
            _jasperVault,
            address(manager),
            _owner,
            _methodologist
        );
        return address(manager);
    }

    /**
     * ONLY DEPLOYER: Wires JasperVault, DelegatedManager, global manager extensions, and modules together
     * into a functioning package.
     *
     * NOTE: When migrating to this manager system from an existing JasperVault, the JasperVault's current manager address
     * must be reset to point at the newly deployed DelegatedManager contract in a separate, final transaction.
     *
     * @param  _jasperVault                Instance of the JasperVault
     * @param  _extensions              List of addresses of extensions which need to be initialized
     * @param  _initializeBytecode      List of bytecode encoded calls to relevant target's initialize function
     */
    function initialize(
        IJasperVault _jasperVault,
        address[] memory _extensions,
        bytes[] memory _initializeBytecode
    ) external {
        require(
            initializeState[_jasperVault].isPending,
            "Manager must be awaiting initialization"
        );
        require(
            msg.sender == initializeState[_jasperVault].deployer,
            "Only deployer can initialize manager"
        );
        _extensions.validatePairsWithArray(_initializeBytecode);

        IDelegatedManager manager = initializeState[_jasperVault].manager;

        // If the JasperVault was factory-deployed & factory is its current `manager`, transfer
        // managership to the new DelegatedManager
        if (_jasperVault.manager() == address(this)) {
            _jasperVault.setManager(address(manager));
        }

        _initializeExtensions(manager, _extensions, _initializeBytecode);

        _setManagerState(
            manager,
            initializeState[_jasperVault].owner,
            initializeState[_jasperVault].methodologist
        );

        delete initializeState[_jasperVault];
        jasperVaultInitial[address(_jasperVault)] = true;
        emit DelegatedManagerInitialized(_jasperVault, manager);
    }

    /* ============ Internal Functions ============ */

    /**
     * Deploys a JasperVault, setting this factory as its manager temporarily, pending initialization.
     * Managership is transferred to a newly created DelegatedManager during `initialize`
     *
     * @param _components       List of addresses of components for initial Positions
     * @param _units            List of units. Each unit is the # of components per 10^18 of a JasperVault
     * @param _modules          List of modules to enable. All modules must be approved by the Controller
     * @param _name             Name of the JasperVault
     * @param _symbol           Symbol of the JasperVault
     *
     * @return Address of created JasperVault;
     */
    function _deploySet(
        address[] memory _components,
        int256[] memory _units,
        address[] memory _modules,
        string memory _name,
        string memory _symbol,
        address _masterToken,
        uint256 _followFee,
        uint256 _maxFollowFee,
        uint256 _profitShareFee
    ) internal returns (IJasperVault) {
        address jasperVault = setTokenFactory.create(
            _components,
            _units,
            _modules,
            address(this),
            _name,
            _symbol,
            _masterToken,
            _followFee,
            _maxFollowFee,
            _profitShareFee
        );

        return IJasperVault(jasperVault);
    }

    /**
     * Deploys a DelegatedManager. Sets owner and methodologist roles to address(this) and the resulting manager address is
     * saved to the ManagerCore.
     *
     * @param  _jasperVault         Instance of JasperVault to migrate to the DelegatedManager system
     * @param  _extensions       List of extensions authorized for the DelegateManager
     * @param  _operators        List of operators authorized for the DelegateManager
     * @param  _assets           List of assets DelegateManager can trade. When empty, asset allow list is not enforced
     *
     * @return Address of created DelegatedManager
     */
    function _deployManager(
        IJasperVault _jasperVault,
        address[] memory _extensions,
        address[] memory _operators,
        address[] memory _assets,
        address[] memory _adapters,
        uint256 _delay
    ) internal returns (DelegatedManager) {
        // If asset array is empty, manager's useAssetAllowList will be set to false
        // and the asset allow list is not enforced
        bool useAssetAllowlist = _assets.length > 0;
        bool useAdapterAllowlist = _adapters.length > 0;
        DelegatedManager newManager = new DelegatedManager(
            _jasperVault,
            address(this),
            address(this),
            _extensions,
            _operators,
            _assets,
            _adapters,
            useAssetAllowlist,
            useAdapterAllowlist,
            _delay
        );

        // Registers manager with ManagerCore
        managerCore.addManager(address(newManager));

        emit DelegatedManagerCreated(_jasperVault, newManager, msg.sender);

        return newManager;
    }

    /**
     * Initialize extensions on the DelegatedManager. Checks that extensions are tracked on the ManagerCore and that the
     * provided bytecode targets the input manager.
     *
     * @param  _manager                  Instance of DelegatedManager
     * @param  _extensions               List of addresses of extensions to initialize
     * @param  _initializeBytecode       List of bytecode encoded calls to relevant extensions's initialize function
     */
    function _initializeExtensions(
        IDelegatedManager _manager,
        address[] memory _extensions,
        bytes[] memory _initializeBytecode
    ) internal {
        for (uint256 i = 0; i < _extensions.length; i++) {
            address extension = _extensions[i];
            require(
                managerCore.isExtension(extension),
                "Target must be ManagerCore-enabled Extension"
            );

            bytes memory initializeBytecode = _initializeBytecode[i];

            // Each input initializeBytecode is a varible length bytes array which consists of a 32 byte prefix for the
            // length parameter, a 4 byte function selector, a 32 byte DelegatedManager address, and any additional parameters
            // as shown below:
            // [32 bytes - length parameter, 4 bytes - function selector, 32 bytes - DelegatedManager address, additional parameters]
            // It is required that the input DelegatedManager address is the DelegatedManager address corresponding to the caller
            address inputManager;
            assembly {
                inputManager := mload(add(initializeBytecode, 36))
            }
            require(
                inputManager == address(_manager),
                "Must target correct DelegatedManager"
            );

            // Because we validate uniqueness of _extensions only one transaction can be sent to each extension during this
            // transaction. Due to this no extension can be used for any JasperVault transactions other than initializing these contracts
            extension.functionCallWithValue(initializeBytecode, 0);
        }
    }

    /**
     * Stores temporary creation metadata during the contract creation step. Data is retrieved, read and
     * finally deleted during `initialize`.
     *
     * @param  _jasperVault         Instance of JasperVault
     * @param  _manager          Address of DelegatedManager created for JasperVault
     * @param  _owner            Address that will be given the `owner` DelegatedManager's role on initialization
     * @param  _methodologist    Address that will be given the `methodologist` DelegatedManager's role on initialization
     */
    function _setInitializationState(
        IJasperVault _jasperVault,
        address _manager,
        address _owner,
        address _methodologist
    ) internal {
        initializeState[_jasperVault] = InitializeParams({
            deployer: msg.sender,
            owner: _owner,
            methodologist: _methodologist,
            manager: IDelegatedManager(_manager),
            isPending: true
        });
    }

    /**
     * Initialize fee settings on DelegatedManager and transfer `owner` and `methodologist` roles.
     *
     * @param  _manager                 Instance of DelegatedManager
     * @param  _owner                   Address that will be given the `owner` DelegatedManager's role
     */
    function _setManagerState(
        IDelegatedManager _manager,
        address _owner,
        address _methodologist
    ) internal {
        _manager.transferOwnership(_owner);
        _manager.setMethodologist(_methodologist);
    }

    /**
     * Validates that all components currently held by the Set are on the asset allow list. Validate that the manager is
     * deployed with at least one extension in the PENDING state.
     *
     * @param  _components       List of addresses of components for initial/current Set positions
     * @param  _extensions       List of extensions authorized for the DelegateManager
     * @param  _assets           List of assets DelegateManager can trade. When empty, asset allow list is not enforced
     */
    function _validateManagerParameters(
        address[] memory _components,
        address[] memory _extensions,
        address[] memory _assets
    ) internal pure {
        require(_extensions.length > 0, "Must have at least 1 extension");

        if (_assets.length != 0) {
            _validateComponentsIncludedInAssetsList(_components, _assets);
        }
    }

    /**
     * Validates that all JasperVault components are included in the assets whitelist. This prevents the
     * DelegatedManager from being initialized with some components in an untrade-able state.
     *
     * @param _components       List of addresses of components for initial Positions
     * @param  _assets          List of assets DelegateManager can trade.
     */
    function _validateComponentsIncludedInAssetsList(
        address[] memory _components,
        address[] memory _assets
    ) internal pure {
        for (uint256 i = 0; i < _components.length; i++) {
            require(
                _assets.contains(_components[i]),
                "Asset list must include all components"
            );
        }
    }
}

