// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {IERC20} from "./ERC20_IERC20.sol";

interface IKSZapRouter {
  event ClientData(bytes _clientData);
  event ZapExecuted(
    uint8 indexed _dexType,
    IERC20 indexed _srcToken,
    uint256 indexed _srcAmount,
    address _validator,
    address _executor,
    bytes _zapInfo,
    bytes _extraData,
    bytes _initialData,
    bytes _zapResults
  );
  event ExecutorWhitelisted(address indexed _executor, bool indexed _grantOrRevoke);
  event ValidatorWhitelisted(address indexed _validator, bool indexed _grantOrRevoke);
  event TokenCollected(IERC20 _token, uint256 _amount, bool _isNative, bool _isPermit);

  /// @notice Contains general data for zapping and validation
  /// @param dexType dex id to interact with, following DexType in IZapDexEnum
  /// @param srcToken token to be used for zapping
  /// @param srcAmount amount to be used for zapping
  /// @param zapInfo extra info, depends on each dex type
  /// @param extraData extra data to be used for validation
  /// @param permitData only when using permit for src token
  struct ZapDescription {
    uint8 dexType;
    IERC20 srcToken;
    uint256 srcAmount;
    bytes zapInfo;
    bytes extraData;
    bytes permitData;
  }

  /// @notice Contains execution data for zapping
  /// @param validator validator address, must be whitelisted one
  /// @param executor zap executor address, must be whitelisted one
  /// @param deadline make sure the request is not expired yet
  /// @param executorData data for zap execution
  /// @param clientData for events and tracking purposes
  struct ZapExecutionData {
    address validator;
    address executor;
    uint32 deadline;
    bytes executorData;
    bytes clientData;
  }

  /// @notice Zap In with given data, returns the zapResults from execution
  function zapIn(
    ZapDescription calldata _desc,
    ZapExecutionData calldata _exe
  ) external returns (bytes memory zapResults);

  /// @notice Zap In with given data using native token, returns the zapResults from execution
  function zapInWithNative(
    ZapDescription calldata _desc,
    ZapExecutionData calldata _exe
  ) external payable returns (bytes memory zapResults);

  function whitelistExecutors(address[] calldata _executors, bool _grantOrRevoke) external;
  function whitelistValidators(address[] calldata _validators, bool _grantOrRevoke) external;
}

