// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { PythStructs } from "./IPyth.sol";
import { IPythAdapter } from "./IPythAdapter.sol";
import { IReadablePyth } from "./IReadablePyth.sol";

contract PythAdapter is OwnableUpgradeable, IPythAdapter {
  // errors
  error PythAdapter_BrokenPythPrice();
  error PythAdapter_ConfidenceRatioTooHigh();
  error PythAdapter_OnlyUpdater();
  error PythAdapter_UnknownAssetId();
  error PythAdapter_WrongArgs();

  // state variables
  IReadablePyth public pyth;
  // mapping of our asset id to Pyth's price id
  mapping(bytes32 => IPythAdapter.PythPriceConfig) public configs;

  // events
  event LogSetConfig(bytes32 indexed _assetId, bytes32 _pythPriceId, bool _inverse);
  event LogSetPyth(address _oldPyth, address _newPyth);

  function initialize(address _pyth) external initializer {
    OwnableUpgradeable.__Ownable_init();

    pyth = IReadablePyth(_pyth);
  }

  /// @notice Set the Pyth price id for the given asset.
  /// @param _assetId The asset address to set.
  /// @param _pythPriceId The Pyth price id to set.
  function setConfig(bytes32 _assetId, bytes32 _pythPriceId, bool _inverse) external onlyOwner {
    PythPriceConfig memory _config = configs[_assetId];

    _config.pythPriceId = _pythPriceId;
    _config.inverse = _inverse;
    emit LogSetConfig(_assetId, _pythPriceId, _inverse);

    configs[_assetId] = _config;
  }

  function setConfigs(
    bytes32[] calldata _assetIds,
    bytes32[] calldata _pythPriceIds,
    bool[] calldata _inverses
  ) external onlyOwner {
    if (_assetIds.length != _pythPriceIds.length || _pythPriceIds.length != _inverses.length)
      revert PythAdapter_WrongArgs();
    PythPriceConfig memory _config;
    for (uint256 i = 0; i < _assetIds.length; ) {
      _config = configs[_assetIds[i]];
      _config.pythPriceId = _pythPriceIds[i];
      _config.inverse = _inverses[i];
      emit LogSetConfig(_assetIds[i], _pythPriceIds[i], _inverses[i]);

      configs[_assetIds[i]] = _config;

      unchecked {
        ++i;
      }
    }
  }

  /// @notice convert Pyth's price to uint256.
  /// @dev This is partially taken from https://github.com/pyth-network/pyth-crosschain/blob/main/target_chains/ethereum/examples/oracle_swap/contract/src/OracleSwap.sol#L92
  /// @param _priceStruct The Pyth's price struct to convert.
  /// @param _targetDecimals The target decimals to convert to.
  /// @param _shouldInvert Whether should invert(^-1) the final result or not.
  function _convertToUint256(
    PythStructs.Price memory _priceStruct,
    bool /*_isMax*/,
    uint8 _targetDecimals,
    bool _shouldInvert
  ) private pure returns (uint256) {
    if (_priceStruct.price <= 0 || _priceStruct.expo > 0 || _priceStruct.expo < -255) {
      revert PythAdapter_BrokenPythPrice();
    }

    uint8 _priceDecimals = uint8(uint32(-1 * _priceStruct.expo));

    uint64 _price = uint64(_priceStruct.price);

    uint256 _price256;
    if (_targetDecimals - _priceDecimals >= 0) {
      _price256 = uint256(_price) * 10 ** uint32(_targetDecimals - _priceDecimals);
    } else {
      _price256 = uint256(_price) / 10 ** uint32(_priceDecimals - _targetDecimals);
    }

    if (!_shouldInvert) {
      return _price256;
    }

    // Quote inversion. This is an intention to support the price like USD/JPY.
    {
      // Safe div 0 check, possible when _priceStruct.price == _priceStruct.conf
      if (_price256 == 0) return 0;

      // Formula: inverted price = 10^2N / priceEN, when N = target decimal
      //
      // Example: Given _targetDecimals = 30, inverted quote price can be calculated as followed.
      // inverted price = 10^60 / priceE30
      return 10 ** uint32(_targetDecimals * 2) / _price256;
    }
  }

  /// @notice Validate Pyth's confidence with given threshold. Revert if confidence ratio is too high.
  /// @dev To bypass the confidence check, the user can submit threshold = 1 ether
  /// @param _priceStruct The Pyth's price struct to convert.
  /// @param _confidenceThreshold The acceptable threshold confidence ratio. ex. _confidenceRatio = 0.01 ether means 1%
  function _validateConfidence(PythStructs.Price memory _priceStruct, uint32 _confidenceThreshold) private pure {
    if (_priceStruct.price < 0) revert PythAdapter_BrokenPythPrice();

    // Revert if confidence ratio is too high
    if (_priceStruct.conf * 1e6 > _confidenceThreshold * uint64(_priceStruct.price))
      revert PythAdapter_ConfidenceRatioTooHigh();
  }

  /// @notice Get the latest price of the given asset. Returned price is in 30 decimals.
  /// @dev The price returns here can be staled.
  /// @param _assetId The asset id to get price.
  /// @param _isMax Whether to get the max price.
  /// @param _confidenceThreshold The acceptable threshold confidence ratio. ex. _confidenceRatio = 0.01 ether means 1%
  function getLatestPrice(
    bytes32 _assetId,
    bool _isMax,
    uint32 _confidenceThreshold
  ) external view returns (uint256, uint256) {
    // SLOAD
    IPythAdapter.PythPriceConfig memory _config = configs[_assetId];

    if (_config.pythPriceId == bytes32(0)) revert PythAdapter_UnknownAssetId();
    PythStructs.Price memory _price = pyth.getPriceUnsafe(_config.pythPriceId);
    _validateConfidence(_price, _confidenceThreshold);

    return (_convertToUint256(_price, _isMax, 30, _config.inverse), _price.publishTime);
  }

  function getConfigByAssetId(bytes32 _assetId) external view returns (IPythAdapter.PythPriceConfig memory) {
    return configs[_assetId];
  }

  /**
   * Setter
   */
  /// @notice Set new Pyth contract address.
  /// @param _newPyth New Pyth contract address.
  function setPyth(address _newPyth) external onlyOwner {
    emit LogSetPyth(address(pyth), _newPyth);
    pyth = IReadablePyth(_newPyth);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}

