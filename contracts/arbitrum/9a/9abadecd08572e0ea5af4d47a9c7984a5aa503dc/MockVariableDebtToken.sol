// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {VariableDebtToken} from "./tokenization_VariableDebtToken.sol";
import {IPool} from "./IPool.sol";

contract MockVariableDebtToken is VariableDebtToken {
  constructor(IPool pool) VariableDebtToken(pool) {}

  function getRevision() internal pure override returns (uint256) {
    return 0x3;
  }
}

