// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.15;

import { Executable } from "./Executable.sol";
import { UseStore, Write } from "./UseStore.sol";
import { OperationStorage } from "./OperationStorage.sol";
import { ILendingPool } from "./ILendingPool.sol";
import { WithdrawData } from "./types_Aave.sol";
import { AAVE_POOL } from "./types_Aave.sol";
import { IPoolV3 } from "./IPoolV3.sol";

/**
 * @title Withdraw | AAVE V3 Action contract
 * @notice Withdraw collateral from AAVE's lending pool
 */
contract AaveV3Withdraw is Executable, UseStore {
  using Write for OperationStorage;

  constructor(address _registry) UseStore(_registry) {}

  /**
   * @param data Encoded calldata that conforms to the WithdrawData struct
   */
  function execute(bytes calldata data, uint8[] memory) external payable override {
    WithdrawData memory withdraw = parseInputs(data);

    uint256 amountWithdrawn = IPoolV3(registry.getRegisteredService(AAVE_POOL)).withdraw(
      withdraw.asset,
      withdraw.amount,
      withdraw.to
    );

    store().write(bytes32(amountWithdrawn));
  }

  function parseInputs(bytes memory _callData) public pure returns (WithdrawData memory params) {
    return abi.decode(_callData, (WithdrawData));
  }
}

