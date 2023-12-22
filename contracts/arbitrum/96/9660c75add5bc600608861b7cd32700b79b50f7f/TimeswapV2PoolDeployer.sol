// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {TimeswapV2Pool} from "./TimeswapV2Pool.sol";

import {ITimeswapV2PoolDeployer} from "./ITimeswapV2PoolDeployer.sol";

/// @title Capable of deploying Timeswap V2 Pool
/// @author Timeswap Labs
contract TimeswapV2PoolDeployer is ITimeswapV2PoolDeployer {
  struct Parameter {
    address poolFactory;
    address optionPair;
    uint256 transactionFee;
    uint256 protocolFee;
  }

  /* ===== MODEL ===== */

  /// @inheritdoc ITimeswapV2PoolDeployer
  Parameter public override parameter;

  /* ===== UPDATE ===== */
  /// @dev deploy the pool contract
  /// @param poolFactory address of the pool factory
  /// @param optionPair address of the option pair contract
  /// @param transactionFee transaction fee to be used in the pool contract
  /// @param protocolFee protocol fee to be used in the pool contract
  function deploy(
    address poolFactory,
    address optionPair,
    uint256 transactionFee,
    uint256 protocolFee
  ) internal returns (address poolPair) {
    parameter = Parameter({
      poolFactory: poolFactory,
      optionPair: optionPair,
      transactionFee: transactionFee,
      protocolFee: protocolFee
    });

    poolPair = address(new TimeswapV2Pool{salt: keccak256(abi.encode(optionPair))}());

    delete parameter;
  }
}

