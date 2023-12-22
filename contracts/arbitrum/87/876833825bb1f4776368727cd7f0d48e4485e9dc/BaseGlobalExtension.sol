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

import {AddressArrayUtils} from "./AddressArrayUtils.sol";
import {IJasperVault} from "./IJasperVault.sol";

import {IDelegatedManager} from "./IDelegatedManager.sol";
import {IManagerCore} from "./IManagerCore.sol";

import {IController} from "./IController.sol";
import {ResourceIdentifier} from "./ResourceIdentifier.sol";

/**
 * @title BaseGlobalExtension
 * @author Set Protocol
 *
 * Abstract class that houses common global extension-related functions. Global extensions must
 * also have their own initializeExtension function (not included here because interfaces will vary).
 */
abstract contract BaseGlobalExtension {
    using AddressArrayUtils for address[];
    using ResourceIdentifier for IController;
    /* ============ Events ============ */

    event ExtensionRemoved(
        address indexed _jasperVault,
        address indexed _delegatedManager
    );

    /* ============ State Variables ============ */

    // Address of the ManagerCore
    IManagerCore public immutable managerCore;

    // Mapping from Set Token to DelegatedManager
    mapping(IJasperVault => IDelegatedManager) public setManagers;

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the JasperVault manager contract owner
     */
    modifier onlyOwner(IJasperVault _jasperVault) {
        require(msg.sender == _manager(_jasperVault).owner(), "Must be owner");
        _;
    }

    /**
     * Throws if the sender is not the JasperVault methodologist
     */
    modifier onlyMethodologist(IJasperVault _jasperVault) {
        require(
            msg.sender == _manager(_jasperVault).methodologist(),
            "Must be methodologist"
        );
        _;
    }

    modifier onlyUnSubscribed(IJasperVault _jasperVault) {
        require(
            _manager(_jasperVault).subscribeStatus()==2,
            "jasperVault not unsubscribed"
        );
        _;
    }


    modifier onlySubscribed(IJasperVault _jasperVault) {
        require(
            _manager(_jasperVault).subscribeStatus()==1,
            "jasperVault not subscribed"
        );
        _;
    }


    modifier onlySettle(IJasperVault _jasperVault) {
        require(
            _manager(_jasperVault).subscribeStatus()==0,
            "jasperVault not unsettle"
        );
        _;
    }


    modifier onlyNotSubscribed(IJasperVault _jasperVault) {
        require(
            _manager(_jasperVault).subscribeStatus()!=1,
            "jasperVault not unsettle"
        );
        _;
    }

    /**
     * Throws if the sender is not a JasperVault operator
     */
    modifier onlyOperator(IJasperVault _jasperVault) {
        require(
            _manager(_jasperVault).operatorAllowlist(msg.sender),
            "Must be approved operator"
        );
        _;
    }

    modifier ValidAdapter(
        IJasperVault _jasperVault,
        address _module,
        string memory _integrationName
    ) {
        bool isValid = ValidAdapterByModule(
            _jasperVault,
            _module,
            _integrationName
        );
        require(isValid, "Must be allowed adapter");
        _;
    }

    /**
     * Throws if the sender is not the JasperVault manager contract owner or if the manager is not enabled on the ManagerCore
     */
    modifier onlyOwnerAndValidManager(IDelegatedManager _delegatedManager) {
        require(msg.sender == _delegatedManager.owner(), "Must be owner");
        require(
            managerCore.isManager(address(_delegatedManager)),
            "Must be ManagerCore-enabled manager"
        );
        _;
    }

    /**
     * Throws if asset is not allowed to be held by the Set
     */
    modifier onlyAllowedAsset(IJasperVault _jasperVault, address _asset) {
        require(
            _manager(_jasperVault).isAllowedAsset(_asset),
            "Must be allowed asset"
        );
        _;
    }

    /* ============ Constructor ============ */

    /**
     * Set state variables
     *
     * @param _managerCore             Address of managerCore contract
     */
    constructor(IManagerCore _managerCore) public {
        managerCore = _managerCore;
    }

    /* ============ External Functions ============ */

    function ValidAdapterByModule(
        IJasperVault _jasperVault,
        address _module,
        string memory _integrationName
    ) public view returns (bool) {
        address controller = _jasperVault.controller();
        bytes32 _integrationHash = keccak256(bytes(_integrationName));
        address adapter = IController(controller)
            .getIntegrationRegistry()
            .getIntegrationAdapterWithHash(_module, _integrationHash);
        return _manager(_jasperVault).isAllowedAdapter(adapter);
    }

    /**
     * ONLY MANAGER: Deletes JasperVault/Manager state from extension. Must only be callable by manager!
     */
    function removeExtension() external virtual;

    /* ============ Internal Functions ============ */

    /**
     * Invoke call from manager
     *
     * @param _delegatedManager      Manager to interact with
     * @param _module                Module to interact with
     * @param _encoded               Encoded byte data
     */
    function _invokeManager(
        IDelegatedManager _delegatedManager,
        address _module,
        bytes memory _encoded
    ) internal {
        _delegatedManager.interactManager(_module, _encoded);
    }

    /**
     * Internal function to grab manager of passed JasperVault from extensions data structure.
     *
     * @param _jasperVault         JasperVault who's manager is needed
     */
    function _manager(
        IJasperVault _jasperVault
    ) internal view returns (IDelegatedManager) {
        return setManagers[_jasperVault];
    }

    /**
     * Internal function to initialize extension to the DelegatedManager.
     *
     * @param _jasperVault             Instance of the JasperVault corresponding to the DelegatedManager
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
    function _initializeExtension(
        IJasperVault _jasperVault,
        IDelegatedManager _delegatedManager
    ) internal {
        setManagers[_jasperVault] = _delegatedManager;
        _delegatedManager.initializeExtension();
    }

    /**
     * ONLY MANAGER: Internal function to delete JasperVault/Manager state from extension
     */
    function _removeExtension(
        IJasperVault _jasperVault,
        IDelegatedManager _delegatedManager
    ) internal {
        require(
            msg.sender == address(_manager(_jasperVault)),
            "Must be Manager"
        );

        delete setManagers[_jasperVault];

        emit ExtensionRemoved(
            address(_jasperVault),
            address(_delegatedManager)
        );
    }
}

