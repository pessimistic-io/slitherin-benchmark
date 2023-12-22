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
pragma experimental "ABIEncoderV2";

import {IJasperVault} from "./IJasperVault.sol";
import {IWETH} from "./external_IWETH.sol";
import {IWrapModuleV2} from "./IWrapModuleV2.sol";

import {BaseGlobalExtension} from "./BaseGlobalExtension.sol";
import {IDelegatedManager} from "./IDelegatedManager.sol";
import {IManagerCore} from "./IManagerCore.sol";
import {ISignalSuscriptionModule} from "./ISignalSuscriptionModule.sol";

/**
 * @title WrapExtension
 * @author Set Protocol
 *
 * Smart contract global extension which provides DelegatedManager operator(s) the ability to wrap ERC20 and Ether positions
 * via third party protocols.
 *
 * Some examples of wrap actions include wrapping, DAI to cDAI (Compound) or Dai to aDai (AAVE).
 */
contract WrapExtension is BaseGlobalExtension {
    /* ============ Events ============ */

    event WrapExtensionInitialized(
        address indexed _jasperVault,
        address indexed _delegatedManager
    );
    event InvokeFail(
        address indexed _manage,
        address _wrapModule,
        string _reason,
        bytes _callData
    );
    struct WrapInfo {
        address underlyingToken;
        address wrappedToken;
        int256 underlyingUnits;
        string integrationName;
        bytes wrapData;
    }
    struct UnwrapInfo {
        address underlyingToken;
        address wrappedToken;
        int256 wrappedUnits;
        string integrationName;
        bytes unwrapData;
    }
    /* ============ State Variables ============ */

    // Instance of WrapModuleV2
    IWrapModuleV2 public immutable wrapModule;
    ISignalSuscriptionModule public immutable signalSuscriptionModule;

    /* ============ Constructor ============ */

    /**
     * Instantiate with ManagerCore address and WrapModuleV2 address.
     *
     * @param _managerCore              Address of ManagerCore contract
     * @param _wrapModule               Address of WrapModuleV2 contract
     */
    constructor(
        IManagerCore _managerCore,
        IWrapModuleV2 _wrapModule,
        ISignalSuscriptionModule _signalSuscriptionModule
    ) public BaseGlobalExtension(_managerCore) {
        wrapModule = _wrapModule;
        signalSuscriptionModule = _signalSuscriptionModule;
    }

    /* ============ External Functions ============ */

    /**
     * ONLY OWNER: Initializes WrapModuleV2 on the JasperVault associated with the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the WrapModuleV2 for
     */
    function initializeModule(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        _initializeModule(_delegatedManager.jasperVault(), _delegatedManager);
    }

    /**
     * ONLY OWNER: Initializes WrapExtension to the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
    function initializeExtension(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);

        emit WrapExtensionInitialized(
            address(jasperVault),
            address(_delegatedManager)
        );
    }

    /**
     * ONLY OWNER: Initializes WrapExtension to the DelegatedManager and TradeModule to the JasperVault
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
    function initializeModuleAndExtension(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);
        _initializeModule(jasperVault, _delegatedManager);

        emit WrapExtensionInitialized(
            address(jasperVault),
            address(_delegatedManager)
        );
    }

    /**
     * ONLY MANAGER: Remove an existing JasperVault and DelegatedManager tracked by the WrapExtension
     */
    function removeExtension() external override {
        IDelegatedManager delegatedManager = IDelegatedManager(msg.sender);
        IJasperVault jasperVault = delegatedManager.jasperVault();

        _removeExtension(jasperVault, delegatedManager);
    }

    function wrap(
        IJasperVault _jasperVault,
        WrapInfo memory _wrapInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, _wrapInfo.wrappedToken)
        ValidAdapter(
            _jasperVault,
            address(wrapModule),
            _wrapInfo.integrationName
        )
    {
        bytes memory callData = abi.encodeWithSelector(
            IWrapModuleV2.wrap.selector,
            _jasperVault,
            _wrapInfo.underlyingToken,
            _wrapInfo.wrappedToken,
            _wrapInfo.underlyingUnits,
            _wrapInfo.integrationName,
            _wrapInfo.wrapData
        );
        _invokeManager(_manager(_jasperVault), address(wrapModule), callData);
    }

    function wrapWithEther(
        IJasperVault _jasperVault,
        WrapInfo memory _wrapInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(
            _jasperVault,
            address(wrapModule),
            _wrapInfo.integrationName
        )
    {
        bytes memory callData = abi.encodeWithSelector(
            IWrapModuleV2.wrapWithEther.selector,
            _jasperVault,
            _wrapInfo.wrappedToken,
            _wrapInfo.underlyingUnits,
            _wrapInfo.integrationName,
            _wrapInfo.wrapData
        );
        _invokeManager(_manager(_jasperVault), address(wrapModule), callData);
    }

    function unwrap(
        IJasperVault _jasperVault,
        UnwrapInfo memory _unwrapInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, _unwrapInfo.underlyingToken)
        ValidAdapter(
            _jasperVault,
            address(wrapModule),
            _unwrapInfo.integrationName
        )
    {
        bytes memory callData = abi.encodeWithSelector(
            IWrapModuleV2.unwrap.selector,
            _jasperVault,
            _unwrapInfo.underlyingToken,
            _unwrapInfo.wrappedToken,
            _unwrapInfo.wrappedUnits,
            _unwrapInfo.integrationName,
            _unwrapInfo.unwrapData
        );
        _invokeManager(_manager(_jasperVault), address(wrapModule), callData);
    }

    function unwrapWithEther(
        IJasperVault _jasperVault,
        UnwrapInfo memory _unwrapInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, address(wrapModule.weth()))
        ValidAdapter(
            _jasperVault,
            address(wrapModule),
            _unwrapInfo.integrationName
        )
    {
        bytes memory callData = abi.encodeWithSelector(
            IWrapModuleV2.unwrapWithEther.selector,
            _jasperVault,
            _unwrapInfo.wrappedToken,
            _unwrapInfo.wrappedUnits,
            _unwrapInfo.integrationName,
            _unwrapInfo.unwrapData
        );
        _invokeManager(_manager(_jasperVault), address(wrapModule), callData);
    }

    function wrapWithFollowers(
        IJasperVault _jasperVault,
        WrapInfo memory _wrapInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, _wrapInfo.wrappedToken)
        ValidAdapter(
            _jasperVault,
            address(wrapModule),
            _wrapInfo.integrationName
        )
    {


       bytes memory  callData = abi.encodeWithSelector(
            IWrapModuleV2.wrap.selector,
            _jasperVault,
            _wrapInfo.underlyingToken,
            _wrapInfo.wrappedToken,
            _wrapInfo.underlyingUnits,
            _wrapInfo.integrationName,
            _wrapInfo.wrapData
        );
        _invokeManager(_manager(_jasperVault), address(wrapModule), callData);
        _executeWrapWithFollowers(_jasperVault, _wrapInfo);
        callData = abi.encodeWithSelector(
            ISignalSuscriptionModule.exectueFollowStart.selector,
            address(_jasperVault)
        );
        _invokeManager(_manager(_jasperVault), address(signalSuscriptionModule), callData);
    }

    function _executeWrapWithFollowers(
        IJasperVault _jasperVault,
        WrapInfo memory _wrapInfo
    ) internal {
        address[] memory followers = signalSuscriptionModule.get_followers(
            address(_jasperVault)
        );
        for (uint256 i = 0; i < followers.length; i++) {
            bytes memory callData = abi.encodeWithSelector(
                IWrapModuleV2.wrap.selector,
                IJasperVault(followers[i]),
                _wrapInfo.underlyingToken,
                _wrapInfo.wrappedToken,
                _wrapInfo.underlyingUnits,
                _wrapInfo.integrationName,
                _wrapInfo.wrapData
            );
            _execute(
                _manager(IJasperVault(followers[i])),
                address(wrapModule),
                callData
            );
        }
    }

    function wrapEtherWithFollowers(
        IJasperVault _jasperVault,
        WrapInfo memory _wrapInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(
            _jasperVault,
            address(wrapModule),
            _wrapInfo.integrationName
        )
    {
         bytes memory callData = abi.encodeWithSelector(
            IWrapModuleV2.wrapWithEther.selector,
            _jasperVault,
            _wrapInfo.wrappedToken,
            _wrapInfo.underlyingUnits,
            _wrapInfo.integrationName,
            _wrapInfo.wrapData
        );

        _invokeManager(_manager(_jasperVault), address(wrapModule), callData);
        _executeWrapEtherWithFollowers(_jasperVault, _wrapInfo);
        callData = abi.encodeWithSelector(
            ISignalSuscriptionModule.exectueFollowStart.selector,
            address(_jasperVault)
        );
        _invokeManager(_manager(_jasperVault), address(signalSuscriptionModule), callData);
    }

    function _executeWrapEtherWithFollowers(
        IJasperVault _jasperVault,
        WrapInfo memory _wrapInfo
    ) internal {
        address[] memory followers = signalSuscriptionModule.get_followers(
            address(_jasperVault)
        );
        for (uint256 i = 0; i < followers.length; i++) {
            bytes memory callData = abi.encodeWithSelector(
                IWrapModuleV2.wrap.selector,
                IJasperVault(followers[i]),
                _wrapInfo.wrappedToken,
                _wrapInfo.underlyingUnits,
                _wrapInfo.integrationName,
                _wrapInfo.wrapData
            );
            _execute(
                _manager(IJasperVault(followers[i])),
                address(wrapModule),
                callData
            );
        }
    }

    function unwrapWithFollowers(
        IJasperVault _jasperVault,
        UnwrapInfo memory _unwrapInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, _unwrapInfo.underlyingToken)
        ValidAdapter(
            _jasperVault,
            address(wrapModule),
            _unwrapInfo.integrationName
        )
    {
       bytes memory   callData = abi.encodeWithSelector(
            IWrapModuleV2.unwrap.selector,
            _jasperVault,
            _unwrapInfo.underlyingToken,
            _unwrapInfo.wrappedToken,
            _unwrapInfo.wrappedUnits,
            _unwrapInfo.integrationName,
            _unwrapInfo.unwrapData
        );
        _invokeManager(_manager(_jasperVault), address(wrapModule), callData);
        _executeUnwrapWithFollowers(_jasperVault, _unwrapInfo);
       callData = abi.encodeWithSelector(
            ISignalSuscriptionModule.exectueFollowStart.selector,
            address(_jasperVault)
        );
        _invokeManager(_manager(_jasperVault), address(signalSuscriptionModule), callData);
    }

    function _executeUnwrapWithFollowers(
        IJasperVault _jasperVault,
        UnwrapInfo memory _unwrapInfo
    ) internal {
        address[] memory followers = signalSuscriptionModule.get_followers(
            address(_jasperVault)
        );
        for (uint256 i = 0; i < followers.length; i++) {
            bytes memory callData = abi.encodeWithSelector(
                IWrapModuleV2.unwrap.selector,
                IJasperVault(followers[i]),
                _unwrapInfo.underlyingToken,
                _unwrapInfo.wrappedToken,
                _unwrapInfo.wrappedUnits,
                _unwrapInfo.integrationName,
                _unwrapInfo.unwrapData
            );
            _execute(
                _manager(IJasperVault(followers[i])),
                address(wrapModule),
                callData
            );
        }
    }

    function unwrapWithEtherWithFollowers(
        IJasperVault _jasperVault,
        UnwrapInfo memory _unwrapInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, address(wrapModule.weth()))
        ValidAdapter(
            _jasperVault,
            address(wrapModule),
            _unwrapInfo.integrationName
        )
    {

       bytes memory   callData = abi.encodeWithSelector(
            IWrapModuleV2.unwrapWithEther.selector,
            _jasperVault,
            _unwrapInfo.wrappedToken,
            _unwrapInfo.wrappedUnits,
            _unwrapInfo.integrationName,
            _unwrapInfo.unwrapData
        );
        _invokeManager(_manager(_jasperVault), address(wrapModule), callData);
        _executeUnwrapEtherWithFollowers(_jasperVault, _unwrapInfo);
       callData = abi.encodeWithSelector(
            ISignalSuscriptionModule.exectueFollowStart.selector,
            address(_jasperVault)
        );
        _invokeManager(_manager(_jasperVault), address(signalSuscriptionModule), callData);
    }

    function _executeUnwrapEtherWithFollowers(
        IJasperVault _jasperVault,
        UnwrapInfo memory _unwrapInfo
    ) internal {
        address[] memory followers = signalSuscriptionModule.get_followers(
            address(_jasperVault)
        );
        for (uint256 i = 0; i < followers.length; i++) {
            bytes memory callData = abi.encodeWithSelector(
                IWrapModuleV2.unwrap.selector,
                IJasperVault(followers[i]),
                _unwrapInfo.wrappedToken,
                _unwrapInfo.wrappedUnits,
                _unwrapInfo.integrationName,
                _unwrapInfo.unwrapData
            );
            _execute(
                _manager(IJasperVault(followers[i])),
                address(wrapModule),
                callData
            );
        }
    }

    /* ============ Internal Functions ============ */
    function _execute(
        IDelegatedManager manager,
        address module,
        bytes memory callData
    ) internal {
        try manager.interactManager(module, callData) {} catch Error(
            string memory reason
        ) {
            emit InvokeFail(address(manager), module, reason, callData);
        }
    }

    /**
     * Internal function to initialize WrapModuleV2 on the JasperVault associated with the DelegatedManager.
     *
     * @param _jasperVault             Instance of the JasperVault corresponding to the DelegatedManager
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the WrapModuleV2 for
     */
    function _initializeModule(
        IJasperVault _jasperVault,
        IDelegatedManager _delegatedManager
    ) internal {
        bytes memory callData = abi.encodeWithSelector(
            IWrapModuleV2.initialize.selector,
            _jasperVault
        );
        _invokeManager(_delegatedManager, address(wrapModule), callData);
    }
}

