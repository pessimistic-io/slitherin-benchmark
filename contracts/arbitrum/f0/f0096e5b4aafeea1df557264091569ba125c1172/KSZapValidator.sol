// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {KSRescue} from "./KSRescue.sol";

import {IKSZapValidator} from "./IKSZapValidator.sol";
import {IBasePositionManager} from "./IBasePositionManager.sol";
import {IUniswapv3NFT} from "./IUniswapv3NFT.sol";

import {IERC20} from "./ERC20_IERC20.sol";

/// @title Contains main logics of a validator when zapping into KyberSwap Elastic/Classic pools
///   and Uniswap v2/v3 + clones
contract KSZapValidator is IKSZapValidator, KSRescue {
  /// @notice Prepare and return validation data before zap, calling internal functions to do the work
  /// @param _dexType type of dex/pool supported by this validator
  /// @param _zapInfo related info of zap to generate data
  function prepareValidationData(
    uint8 _dexType,
    bytes calldata _zapInfo
  ) external view override returns (bytes memory) {
    if (_dexType == uint8(DexType.Elastic)) {
      return _getElasticValidationData(_zapInfo);
    }
    if (_dexType == uint8(DexType.Classic)) {
      return _getClassicValidationData(_zapInfo);
    }
    if (_dexType == uint8(DexType.Uniswapv3)) {
      return _getUniswapV3ValidationData(_zapInfo);
    }
    return new bytes(0);
  }

  /// @notice Validate result after zapping into pool, given initial data and data to validate
  /// @param _dexType type of dex/pool supported by this validator
  /// @param _extraData contains data to compares, for example: min liquidity
  /// @param _initialData contains initial data before zapping
  /// @param _zapResults contains zap results from executor
  function validateData(
    uint8 _dexType,
    bytes calldata _extraData,
    bytes calldata _initialData,
    bytes calldata _zapResults
  ) external view override returns (bool) {
    if (_dexType == uint8(DexType.Elastic)) {
      return _validateElasticResult(_extraData, _initialData);
    }
    if (_dexType == uint8(DexType.Classic)) {
      return _validateClassicResult(_extraData, _initialData);
    }
    if (_dexType == uint8(DexType.Uniswapv3)) {
      return _validateUniswapV3Result(_extraData, _initialData);
    }
    return true;
  }

  // ======================= Prepare data for validation =======================

  /// @notice Generate initial data for validation for KyberSwap Classic and Uniswap v2
  ///  in order to validate, we need to get the initial LP balance of the recipient
  /// @param zapInfo contains info of zap with KyberSwap Classic/Uniswap v2
  ///   should be (pool_address, recipient_address)
  function _getClassicValidationData(bytes calldata zapInfo) internal view returns (bytes memory) {
    ClassicValidationData memory data;
    data.initialData = abi.decode(zapInfo, (ClassicZapData));
    data.initialLiquidity =
      uint128(IERC20(data.initialData.pool).balanceOf(data.initialData.recipient));
    return abi.encode(data);
  }

  /// @notice Generate initial data for validation for KyberSwap Elastic
  ///   2 cases: minting a new position or increase liquidity
  ///   - minting a new position:
  ///     + posID in zapInfo should be 0, then replaced with the expected posID
  ///     + isNewPosition is true
  ///     + initialLiquidity is 0
  ///   - increase liquidity:
  ///     + isNewPosition is false
  ///     + initialLiquidity is the current position liquidity, fetched from Position Manager
  function _getElasticValidationData(bytes calldata zapInfo) internal view returns (bytes memory) {
    ElasticValidationData memory data;
    data.initialData = abi.decode(zapInfo, (ElasticZapData));
    if (data.initialData.posID == 0) {
      // minting new position, posID should be nextTokenId
      data.initialData.posID = IBasePositionManager(data.initialData.posManager).nextTokenId();
      data.isNewPosition = true;
      data.initialLiquidity = 0;
    } else {
      data.isNewPosition = false;
      (IBasePositionManager.Position memory pos,) =
        IBasePositionManager(data.initialData.posManager).positions((data.initialData.posID));
      data.initialLiquidity = pos.liquidity;
    }
    return abi.encode(data);
  }

  /// @notice Generate initial data for validation for Uniswap v3
  ///   2 cases: minting a new position or increase liquidity
  ///   - minting a new position:
  ///     + posID in zapInfo should be 0, then replaced with the curren totalSupply
  ///     + isNewPosition is true
  ///     + initialLiquidity is 0
  ///   - increase liquidity:
  ///     + isNewPosition is false
  ///     + initialLiquidity is the current position liquidity, fetched from Position Manager
  function _getUniswapV3ValidationData(bytes calldata zapInfo) internal view returns (bytes memory) {
    ElasticValidationData memory data;
    data.initialData = abi.decode(zapInfo, (ElasticZapData));
    if (data.initialData.posID == 0) {
      // minting new position, temporary store the total supply here
      data.initialData.posID = IUniswapv3NFT(data.initialData.posManager).totalSupply();
      data.isNewPosition = true;
      data.initialLiquidity = 0;
    } else {
      data.isNewPosition = false;
      (,,,,,,, data.initialLiquidity,,,,) =
        IUniswapv3NFT(data.initialData.posManager).positions(data.initialData.posID);
    }
    return abi.encode(data);
  }

  // ======================= Validate data after zap =======================

  /// @notice Validate result for zapping into KyberSwap Classic/Uniswap v2
  ///   - _extraData is the minLiquidity (for validation)
  ///   - to validate, fetch the current LP balance of the recipient
  ///     then compares with the initialLiquidity, make sure the increment is expected (>= minLiquidity)
  /// @param _extraData just the minLiquidity value, uint128
  /// @param _initialData contains initial data before zap, including initialLiquidity
  function _validateClassicResult(
    bytes calldata _extraData,
    bytes calldata _initialData
  ) internal view returns (bool) {
    ClassicValidationData memory data = abi.decode(_initialData, (ClassicValidationData));
    // getting new lp balance, make sure it should be increased
    uint256 lpBalanceAfter = IERC20(data.initialData.pool).balanceOf(data.initialData.recipient);
    if (lpBalanceAfter < data.initialLiquidity) return false;
    // validate increment in liquidity with min expectation
    uint256 minLiquidity = uint256(abi.decode(_extraData, (uint128)));
    require(minLiquidity > 0, 'zero min_liquidity');
    return (lpBalanceAfter - data.initialLiquidity) >= minLiquidity;
  }

  /// @notice Validate result for zapping into KyberSwap Elastic
  ///   2 cases:
  ///     - new position:
  ///       + _extraData contains (recipient, posTickLower, posTickLower, minLiquidity) where:
  ///         (+) recipient is the owner of the posID
  ///         (+) posTickLower, posTickUpper are matched with position's tickLower/tickUpper
  ///         (+) pool is matched with position's pool
  ///         (+) minLiquidity <= pos.liquidity
  ///     - increase liquidity:
  ///       + _extraData contains minLiquidity, where:
  ///         (+) minLiquidity <= (pos.liquidity - initialLiquidity)
  function _validateElasticResult(
    bytes calldata _extraData,
    bytes calldata _initialData
  ) internal view returns (bool) {
    ElasticValidationData memory data = abi.decode(_initialData, (ElasticValidationData));
    IBasePositionManager posManager = IBasePositionManager(data.initialData.posManager);
    if (data.isNewPosition) {
      // minting a new position, need to validate many data
      ElasticExtraData memory extraData = abi.decode(_extraData, (ElasticExtraData));
      // require owner of the pos id is the recipient
      if (posManager.ownerOf(data.initialData.posID) != extraData.recipient) return false;
      // getting pos info from Position Manager
      (IBasePositionManager.Position memory pos,) = posManager.positions((data.initialData.posID));
      // tick ranges should match
      if (extraData.posTickLower != pos.tickLower || extraData.posTickUpper != pos.tickUpper) {
        return false;
      }
      // poolId should correspond to the pool address
      if (posManager.addressToPoolId(data.initialData.pool) != pos.poolId) return false;
      // new liquidity should match expectation
      require(extraData.minLiquidity > 0, 'zero min_liquidity');
      return pos.liquidity >= extraData.minLiquidity;
    } else {
      // not a new position, only need to verify liquidty increment
      // getting new position liquidity, make sure it is increased
      (IBasePositionManager.Position memory pos,) = posManager.positions((data.initialData.posID));
      if (pos.liquidity < data.initialLiquidity) return false;
      // validate increment in liquidity with min expectation
      uint128 minLiquidity = abi.decode(_extraData, (uint128));
      require(minLiquidity > 0, 'zero min_liquidity');
      return pos.liquidity - data.initialLiquidity >= minLiquidity;
    }
  }

  /// @notice Validate result for zapping into Uniswap V3
  ///   2 cases:
  ///     - new position:
  ///       + posID is the totalSupply, need to fetch the corresponding posID
  ///       + _extraData contains (recipient, posTickLower, posTickLower, minLiquidity) where:
  ///         (+) recipient is the owner of the posID
  ///         (+) posTickLower, posTickUpper are matched with position's tickLower/tickUpper
  ///         (+) pool is matched with position's pool
  ///         (+) minLiquidity <= pos.liquidity
  ///     - increase liquidity:
  ///       + _extraData contains minLiquidity, where:
  ///         (+) minLiquidity <= (pos.liquidity - initialLiquidity)
  function _validateUniswapV3Result(
    bytes calldata _extraData,
    bytes calldata _initialData
  ) internal view returns (bool) {
    ElasticValidationData memory data = abi.decode(_initialData, (ElasticValidationData));
    IUniswapv3NFT posManager = IUniswapv3NFT(data.initialData.posManager);
    if (data.isNewPosition) {
      // minting a new position, need to validate many data
      // Calculate the posID and replace, it should be the last index
      data.initialData.posID = posManager.tokenByIndex(data.initialData.posID);
      ElasticExtraData memory extraData = abi.decode(_extraData, (ElasticExtraData));
      // require owner of the pos id is the recipient
      if (posManager.ownerOf(data.initialData.posID) != extraData.recipient) return false;
      // getting pos info from Position Manager
      (,,,,, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
        posManager.positions(data.initialData.posID);
      // tick ranges should match
      if (extraData.posTickLower != tickLower || extraData.posTickUpper != tickUpper) {
        return false;
      }
      // TODO: poolId should correspond to the pool address
      // if (posManager.addressToPoolId(data.initialData.pool) != pos.poolId) return false;
      // new liquidity should match expectation
      require(extraData.minLiquidity > 0, 'zero min_liquidity');
      return liquidity >= extraData.minLiquidity;
    } else {
      // not a new position, only need to verify liquidty increment
      // getting new position liquidity, make sure it is increased
      (,,,,,,, uint128 newLiquidity,,,,) = posManager.positions(data.initialData.posID);
      if (newLiquidity < data.initialLiquidity) return false;
      // validate increment in liquidity with min expectation
      uint128 minLiquidity = abi.decode(_extraData, (uint128));
      require(minLiquidity > 0, 'zero min_liquidity');
      return newLiquidity - data.initialLiquidity >= minLiquidity;
    }
  }
}

