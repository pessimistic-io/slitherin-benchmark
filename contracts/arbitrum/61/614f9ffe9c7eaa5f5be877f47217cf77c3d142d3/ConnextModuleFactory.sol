// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import {   IConnextModuleFactory,   ConnextModule,   GnosisSafe,   GnosisSafeProxyFactory } from "./IConnextModuleFactory.sol";

contract ConnextModuleFactory is IConnextModuleFactory {
  /// @inheritdoc IConnextModuleFactory
  GnosisSafeProxyFactory public immutable SAFE_FACTORY;

  /**
   * @notice Address used for the GnosisSafe trick
   */
  address internal immutable _FACTORY_ADDRESS;

  constructor(address _safeFactory) {
    SAFE_FACTORY = GnosisSafeProxyFactory(_safeFactory);
    _FACTORY_ADDRESS = address(this);
  }

  /// @inheritdoc IConnextModuleFactory
  function createModule(
    ModuleData calldata _moduleData,
    GnosisSafe _safe
  ) external override returns (ConnextModule _connextModule) {
    _connextModule = new ConnextModule(
        address(_safe),
        address(_safe),
        address(_safe),
        _moduleData.originSender,
        _moduleData.origin,
        _moduleData.connext
    );
  }

  /// @inheritdoc IConnextModuleFactory
  function xReceive(
    bytes32,
    uint256 _amount,
    address,
    address,
    uint32,
    bytes memory _callData
  ) external override returns (bytes memory _returnData) {
    // Amount/asset transfer not supported
    if (_amount > 0) revert xReceive_NotAmountAllowed();

    // Decode message
    (SafeData memory _safeData, ModuleData memory _moduleData, bytes memory _safeTransactionData) =
      abi.decode(_callData, (SafeData, ModuleData, bytes));

    (,, _returnData) = _createSafeAndModule(_safeData, _moduleData, _safeTransactionData);
  }

  /**
   * @notice Creates a GnosisSafe, deploys a module, and then enables the module for the safe
   * @param _safeData The SafeData, required to create the safe
   * @param _moduleData The ModuleData, required to deploy the module
   * @param _safeTransactionData The Safe transaction data to execute after module deployment
   * @return _connextModule Returns the Connext module created
   * @return _safe Returns the GnosisSafe created
   * @return _returnData Returns the transaction return data of the executed transaction.
   */
  function _createSafeAndModule(
    SafeData memory _safeData,
    ModuleData memory _moduleData,
    bytes memory _safeTransactionData
  ) internal returns (ConnextModule _connextModule, GnosisSafe _safe, bytes memory _returnData) {
    // Deploy the Connext Module
    bytes32 _moduleSalt =
      keccak256(abi.encode(_moduleData.originSender, _moduleData.origin, msg.sender, _moduleData.saltNonce));
    _connextModule = new ConnextModule{salt: _moduleSalt}(
      // Hardcoded values are replaced with the correct values
      // after creating the safe (owner, avatar, target, connext)
      _FACTORY_ADDRESS, // Hardcoded for ownership control (owner)
      _FACTORY_ADDRESS, // Hardcoded for ownership control (avatar)
      _FACTORY_ADDRESS, // Hardcoded for ownership control (target)
      _moduleData.originSender,
      _moduleData.origin,
      _FACTORY_ADDRESS // Hardcoded, factory is connext (connext)
    );

    // Set correct target and avatar after deployment
    // GnosisSafeProxy as GnosisSafe
    _safe = GnosisSafe(
      payable(
        SAFE_FACTORY.createProxyWithNonce(
          _safeData.singleton,
          abi.encodeWithSelector(
            GnosisSafe.setup.selector,
            _safeData.owners,
            _safeData.threshold,
            _FACTORY_ADDRESS,
            abi.encodeWithSignature('enableModuleFromFactory(address)', address(_connextModule)),
            address(0),
            address(0),
            uint256(0),
            address(0)
          ),
          _safeData.saltNonce
        )
      )
    );

    // Avatar and Target should ALWAYS be _safe
    _connextModule.setAvatar(address(_safe));
    _connextModule.setTarget(address(_safe));

    if (_safeTransactionData.length != 0) {
      // execute safe transaction though module by bypassing ALL checks
      _returnData = _connextModule.xReceive(
        bytes32(0), 0, address(0), _moduleData.originSender, _moduleData.origin, _safeTransactionData
      );
    }

    // Set correct checks on module
    _connextModule.setConnext(_moduleData.connext);
    _connextModule.transferOwnership(address(_safe));
  }

  /**
   * @notice Reverts if not called from the GnosisSafe on safe creation
   * @param _connextModule The connext module address to enable
   */
  function enableModuleFromFactory(address _connextModule) external {
    GnosisSafe(payable(address(this))).enableModule(_connextModule);
  }
}

