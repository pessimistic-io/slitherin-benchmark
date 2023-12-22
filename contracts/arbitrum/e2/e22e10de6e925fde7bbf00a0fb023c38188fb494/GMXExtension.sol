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
import {IGMXModule} from "./IGMXModule.sol";

import {BaseGlobalExtension} from "./BaseGlobalExtension.sol";
import {IDelegatedManager} from "./IDelegatedManager.sol";
import {IManagerCore} from "./IManagerCore.sol";
import {ISignalSuscriptionModule} from "./ISignalSuscriptionModule.sol";

/**
 * @title GMXExtension
 * @author Set Protocol
 *
 * Smart contract global extension which provides DelegatedManager operator(s) the ability to GMX
 * via third party protocols.
 *
 */
contract GMXExtension is BaseGlobalExtension {
  /* ============ Events ============ */

  event GMXExtensionInitialized(
    address indexed _jasperVault,
    address indexed _delegatedManager
  );

  /* ============ State Variables ============ */

  // Instance of GMXModule
  IGMXModule public immutable GMXModule;
  //    ISignalSuscriptionModule public immutable signalSubscriptionModule;

  /* ============ Constructor ============ */

  /**
   * Instantiate with ManagerCore address and GMXModule address.
   *
   * @param _managerCore              Address of ManagerCore contract
     * @param _GMXModule               Address of GMXModule contract
     */
  constructor(
    IManagerCore _managerCore,
    IGMXModule _GMXModule
  //        ISignalSuscriptionModule _signalSubscriptionModule
  ) public BaseGlobalExtension(_managerCore) {
    GMXModule = _GMXModule;
    //        signalSubscriptionModule = _signalSubscriptionModule;
  }

  /* ============ External Functions ============ */

  /**
   * ONLY OWNER: Initializes GMXModule on the JasperVault associated with the DelegatedManager.
   *
   * @param _delegatedManager     Instance of the DelegatedManager to initialize the GMXModule for jasperVault
     */
  function initializeModule(
    IDelegatedManager _delegatedManager
  ) external onlyOwnerAndValidManager(_delegatedManager) {
    _initializeModule(_delegatedManager.jasperVault(), _delegatedManager);
  }

  /**
   * ONLY OWNER: Initializes GMXExtension to the DelegatedManager.
   *
   * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
  function initializeExtension(
    IDelegatedManager _delegatedManager
  ) external onlyOwnerAndValidManager(_delegatedManager) {
    IJasperVault jasperVault = _delegatedManager.jasperVault();

    _initializeExtension(jasperVault, _delegatedManager);

    emit GMXExtensionInitialized(
      address(jasperVault),
      address(_delegatedManager)
    );
  }

  /**
   * ONLY OWNER: Initializes GMXExtension to the DelegatedManager and TradeModule to the JasperVault
   *
   * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
  function initializeModuleAndExtension(
    IDelegatedManager _delegatedManager
  ) external onlyOwnerAndValidManager(_delegatedManager) {
    IJasperVault jasperVault = _delegatedManager.jasperVault();

    _initializeExtension(jasperVault, _delegatedManager);
    _initializeModule(jasperVault, _delegatedManager);

    emit GMXExtensionInitialized(
      address(jasperVault),
      address(_delegatedManager)
    );
  }

  /**
   * ONLY MANAGER: Remove an existing JasperVault and DelegatedManager tracked by the GMXExtension
   */
  function removeExtension() external override {
    IDelegatedManager delegatedManager = IDelegatedManager(msg.sender);
    IJasperVault jasperVault = delegatedManager.jasperVault();

    _removeExtension(jasperVault, delegatedManager);
  }
  struct PositionData{
    address _underlyingToken;
    address _positionToken;
    int256 _underlyingUnits;
    string  _integrationName;
    bytes  _positionData;
  }
  struct OrderData{
    IJasperVault _jasperVault;
    address _underlyingToken;
    address _positionToken;
    int256 _underlyingUnits;
    string  _integrationName;
    bool   _isIncreasing;
    bytes  _data;
  }
  function increasingPosition(
    IJasperVault _jasperVault,
    PositionData memory _positionData
  )
  external
  onlySettle(_jasperVault)
  onlyOperator(_jasperVault)
  onlyAllowedAsset(_jasperVault, _positionData._positionToken)
  ValidAdapter(
    _jasperVault,
    address(GMXModule),
    _positionData._integrationName
  )
  {
    bytes memory callData = abi.encodeWithSelector(
      IGMXModule.increasingPosition.selector,
      _jasperVault,
      _positionData._underlyingToken,
      _positionData._positionToken,
      _positionData._underlyingUnits,
      _positionData._integrationName,
      _positionData._positionData
    );
    _invokeManager(_manager(_jasperVault), address(GMXModule), callData);
  }
  //    function wrapWithFollowers(
  //        IJasperVault _jasperVault,
  //        WrapInfo memory _wrapInfo
  //    )
  //        external
  //        onlySettle(_jasperVault)
  //        onlyOperator(_jasperVault)
  //        onlyAllowedAsset(_jasperVault, _wrapInfo.wrappedToken)
  //        ValidAdapter(
  //            _jasperVault,
  //            address(GMXModule),
  //            _wrapInfo._integrationName
  //        )
  //    {
  //        bytes memory callData = abi.encodeWithSelector(
  //            ISignalSuscriptionModule.exectueFollowStart.selector,
  //            address(_jasperVault)
  //        );
  //        _invokeManager(_manager(_jasperVault), address(signalSubscriptionModule), callData);
  //
  //        callData = abi.encodeWithSelector(
  //            IGMXModule.wrap.selector,
  //            _jasperVault,
  //            _wrapInfo._underlyingToken,
  //            _wrapInfo.wrappedToken,
  //            _wrapInfo.underlyingUnits,
  //            _wrapInfo._integrationName,
  //            _wrapInfo.wrapData
  //        );
  //        _invokeManager(_manager(_jasperVault), address(GMXModule), callData);
  //        _executeWrapWithFollowers(_jasperVault, _wrapInfo);
  //    }
  //
  //    function _executeWrapWithFollowers(
  //        IJasperVault _jasperVault,
  //        WrapInfo memory _wrapInfo
  //    ) internal {
  //        address[] memory followers = signalSubscriptionModule.get_followers(
  //            address(_jasperVault)
  //        );
  //        for (uint256 i = 0; i < followers.length; i++) {
  //            bytes memory callData = abi.encodeWithSelector(
  //                IGMXModule.wrap.selector,
  //                IJasperVault(followers[i]),
  //                _wrapInfo._underlyingToken,
  //                _wrapInfo.wrappedToken,
  //                _wrapInfo.underlyingUnits,
  //                _wrapInfo._integrationName,
  //                _wrapInfo.wrapData
  //            );
  //            _execute(
  //                _manager(IJasperVault(followers[i])),
  //                address(GMXModule),
  //                callData
  //            );
  //        }
  //    }

  function decreasingPosition(
    IJasperVault _jasperVault,
    PositionData memory _positionData
  )
  external
  onlySettle(_jasperVault)
  onlyOperator(_jasperVault)
  onlyAllowedAsset(_jasperVault, _positionData._underlyingToken)
  ValidAdapter(
    _jasperVault,
    address(GMXModule),
    _positionData._integrationName
  )
  {
    bytes memory callData = abi.encodeWithSelector(
      IGMXModule.decreasingPosition.selector,
      _jasperVault,
      _positionData._underlyingToken,
      _positionData._positionToken,
      _positionData._underlyingUnits,
      _positionData._integrationName,
      _positionData._positionData
    );
    _invokeManager(_manager(_jasperVault), address(GMXModule), callData);
  }

  function swap(
    IJasperVault _jasperVault,
    PositionData memory _positionData
  )
  external
  onlySettle(_jasperVault)
  onlyOperator(_jasperVault)
  onlyAllowedAsset(_jasperVault, _positionData._underlyingToken)
  ValidAdapter(
    _jasperVault,
    address(GMXModule),
    _positionData._integrationName
  )
  {
    bytes memory callData = abi.encodeWithSelector(
      IGMXModule.swap.selector,
      _jasperVault,
      _positionData._underlyingToken,
      _positionData._positionToken,
      _positionData._underlyingUnits,
      _positionData._integrationName,
      _positionData._positionData
    );
    _invokeManager(_manager(_jasperVault), address(GMXModule), callData);
  }

  function creatOrder(
    OrderData memory _orderData
  )
  external
  onlySettle(_orderData._jasperVault)
  onlyOperator(_orderData._jasperVault)
  onlyAllowedAsset(_orderData._jasperVault, _orderData._underlyingToken)
  ValidAdapter(
    _orderData._jasperVault,
    address(GMXModule),
    _orderData._integrationName
  )
  {
    executeOrder(_orderData);
  }
  function executeOrder(OrderData memory _orderData)internal{
    bytes memory callData = abi.encodeWithSelector(
      IGMXModule.creatOrder.selector,
      _orderData._jasperVault,
      _orderData._underlyingToken,
      _orderData._positionToken,
      _orderData._underlyingUnits,
      _orderData._integrationName,
      _orderData._isIncreasing,
      _orderData._data
    );
    _invokeManager(_manager(_orderData._jasperVault), address(GMXModule), callData);
  }



  //    function unwrapWithFollowers(
  //        IJasperVault _jasperVault,
  //        UnwrapInfo memory _unwrapInfo
  //    )
  //        external
  //        onlySettle(_jasperVault)
  //        onlyOperator(_jasperVault)
  //        onlyAllowedAsset(_jasperVault, _unwrapInfo._underlyingToken)
  //        ValidAdapter(
  //            _jasperVault,
  //            address(GMXModule),
  //            _unwrapInfo._integrationName
  //        )
  //    {
  //        bytes memory callData = abi.encodeWithSelector(
  //            ISignalSuscriptionModule.exectueFollowStart.selector,
  //            address(_jasperVault)
  //        );
  //        _invokeManager(_manager(_jasperVault), address(signalSubscriptionModule), callData);
  //        callData = abi.encodeWithSelector(
  //            IGMXModule.unwrap.selector,
  //            _jasperVault,
  //            _unwrapInfo._underlyingToken,
  //            _unwrapInfo.wrappedToken,
  //            _unwrapInfo.wrappedUnits,
  //            _unwrapInfo._integrationName,
  //            _unwrapInfo.unwrapData
  //        );
  //        _invokeManager(_manager(_jasperVault), address(GMXModule), callData);
  //        _executeUnwrapWithFollowers(_jasperVault, _unwrapInfo);
  //    }
  //
  //    function _executeUnwrapWithFollowers(
  //        IJasperVault _jasperVault,
  //        UnwrapInfo memory _unwrapInfo
  //    ) internal {
  //        address[] memory followers = signalSubscriptionModule.get_followers(
  //            address(_jasperVault)
  //        );
  //        for (uint256 i = 0; i < followers.length; i++) {
  //            bytes memory callData = abi.encodeWithSelector(
  //                IGMXModule.unwrap.selector,
  //                IJasperVault(followers[i]),
  //                _unwrapInfo._underlyingToken,
  //                _unwrapInfo.wrappedToken,
  //                _unwrapInfo.wrappedUnits,
  //                _unwrapInfo._integrationName,
  //                _unwrapInfo.unwrapData
  //            );
  //            _execute(
  //                _manager(IJasperVault(followers[i])),
  //                address(GMXModule),
  //                callData
  //            );
  //        }
  //    }
  //
  //
  //    /* ============ Internal Functions ============ */
  //    function _execute(
  //        IDelegatedManager manager,
  //        address module,
  //        bytes memory callData
  //    ) internal {
  //        try manager.interactManager(module, callData) {} catch Error(
  //            string memory reason
  //        ) {
  //            emit InvokeFail(address(manager), module, reason, callData);
  //        }
  //    }

  /**
   * Internal function to initialize GMXModule on the JasperVault associated with the DelegatedManager.
   *
   * @param _jasperVault             Instance of the JasperVault corresponding to the DelegatedManager
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the GMXModule for
     */
  function _initializeModule(
    IJasperVault _jasperVault,
    IDelegatedManager _delegatedManager
  ) internal {
    bytes memory callData = abi.encodeWithSelector(
      IGMXModule.initialize.selector,
      _jasperVault
    );
    _invokeManager(_delegatedManager, address(GMXModule), callData);
  }
}

