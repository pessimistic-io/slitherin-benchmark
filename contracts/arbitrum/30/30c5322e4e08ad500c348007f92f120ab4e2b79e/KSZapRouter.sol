// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {KSRescue} from "./KSRescue.sol";

import {Permitable} from "./Permitable.sol";
import {IKSZapRouter} from "./IKSZapRouter.sol";
import {IZapValidator} from "./IZapValidator.sol";
import {IZapExecutor} from "./IZapExecutor.sol";

import {IERC20} from "./ERC20_IERC20.sol";
import {SafeERC20} from "./utils_SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

/// @notice Main KyberSwap Zap Router to allow users zapping into any dexes
/// It uses Validator to validate the zap result with flexibility, to enable adding more dexes
contract KSZapRouter is IKSZapRouter, Permitable, KSRescue, ReentrancyGuard {
  using SafeERC20 for IERC20;

  mapping(address => bool) public whitelistedExecutor;
  mapping(address => bool) public whitelistedValidator;

  modifier checkDeadline(uint32 _deadline) {
    require(block.timestamp <= _deadline, 'expired');
    _;
  }

  constructor() {}

  /// ==================== Owner ====================
  /// @notice Whitelist executors by the owner, can grant or revoke
  function whitelistExecutors(
    address[] calldata _executors,
    bool _grantOrRevoke
  ) external onlyOwner {
    for (uint256 i = 0; i < _executors.length; i++) {
      whitelistedExecutor[_executors[i]] = _grantOrRevoke;
      emit ExecutorWhitelisted(_executors[i], _grantOrRevoke);
    }
  }

  /// @notice Whitelist validators by the owner, can grant or revoke
  function whitelistValidators(
    address[] calldata _validators,
    bool _grantOrRevoke
  ) external onlyOwner {
    for (uint256 i = 0; i < _validators.length; i++) {
      whitelistedValidator[_validators[i]] = _grantOrRevoke;
      emit ValidatorWhitelisted(_validators[i], _grantOrRevoke);
    }
  }

  /// @inheritdoc IKSZapRouter
  function zapIn(
    ZapDescription calldata _desc,
    ZapExecutionData calldata _exe
  )
    external
    override
    whenNotPaused
    nonReentrant
    checkDeadline(_exe.deadline)
    returns (bytes memory zapResults)
  {
    _handleCollectToken(_desc.srcToken, _desc.srcAmount, _exe.executor, false, _desc.permitData);
    zapResults = _executeZap(_desc, _exe);
  }

  /// @inheritdoc IKSZapRouter
  function zapInWithNative(
    ZapDescription calldata _desc,
    ZapExecutionData calldata _exe
  )
    external
    payable
    override
    whenNotPaused
    nonReentrant
    checkDeadline(_exe.deadline)
    returns (bytes memory zapResults)
  {
    _handleCollectToken(_desc.srcToken, _desc.srcAmount, _exe.executor, true, new bytes(0));
    zapResults = _executeZap(_desc, _exe);
  }

  function _executeZap(
    ZapDescription calldata _desc,
    ZapExecutionData calldata _exe
  ) internal returns (bytes memory zapResults) {
    // getting initial data before zapping
    bytes memory initialData;
    if (_exe.validator != address(0)) {
      require(whitelistedValidator[_exe.validator], 'none whitelist validator');
      initialData =
        IZapValidator(_exe.validator).prepareValidationData(_desc.dexType, _desc.zapInfo);
    }

    // calling executor to execute the zap logic
    zapResults = IZapExecutor(_exe.executor).executeZapIn{value: msg.value}(_exe.executorData);

    // validate data after zapping if needed
    if (_exe.validator != address(0)) {
      bool isValid = IZapValidator(_exe.validator).validateData(
        _desc.dexType, _desc.extraData, initialData, zapResults
      );
      require(isValid, 'validation failed');
    }

    emit ZapExecuted(
      _desc.dexType,
      _desc.srcToken,
      _desc.srcAmount,
      _exe.validator,
      _exe.executor,
      _desc.zapInfo,
      _desc.extraData,
      initialData,
      zapResults
    );
    emit ClientData(_exe.clientData);
  }

  /// @notice Handle collecting token and transfer to executor
  function _handleCollectToken(
    IERC20 _token,
    uint256 _amount,
    address _executor,
    bool _isNative,
    bytes memory _permitData
  ) internal {
    // executor should be whitelisted
    require(whitelistedExecutor[_executor], 'none whitelist executor');
    if (!_isNative) {
      // not using native
      if (_permitData.length > 0) {
        // possibly using permit
        _permit(_token, _amount, _permitData);
      }
      // now collecting token to the recipient, i.e executor
      _token.safeTransferFrom(msg.sender, _executor, _amount);
      // event (token, amount, isNative, isPermit)
      emit TokenCollected(_token, _amount, false, _permitData.length > 0);
      return;
    }

    // using native, validate amount, token address should be validated in the Executor
    require(msg.value == _amount, 'wrong msg.value');
    emit TokenCollected(_token, _amount, true, false);
  }
}

