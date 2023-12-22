// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {IZapValidator} from "./IZapValidator.sol";

interface IKSZapValidator is IZapValidator {
  /// @notice Only need pool address and recipient to get data
  struct ClassicZapData {
    address pool;
    address recipient;
  }

  /// @notice Return KS Classic Zap Data, and initial liquidity of the recipient
  struct ClassicValidationData {
    ClassicZapData initialData;
    uint128 initialLiquidity;
  }

  /// @notice Contains pool, posManage address
  /// posID = 0 -> minting a new position, otherwise increasing to existing one
  struct ElasticZapData {
    address pool;
    address posManager;
    uint256 posID;
  }

  /// @notice Return data for validation purpose
  /// In case minting a new position:
  ///    - In case Elastic: it calculates the expected posID and update the value
  ///    - In case Uniswap v3: it calculates the current total supply
  struct ElasticValidationData {
    ElasticZapData initialData;
    bool isNewPosition;
    uint128 initialLiquidity;
  }

  /// @notice Extra data to be used for validation after zapping
  struct ElasticExtraData {
    address recipient;
    int24 posTickLower;
    int24 posTickUpper;
    uint128 minLiquidity;
  }
}

