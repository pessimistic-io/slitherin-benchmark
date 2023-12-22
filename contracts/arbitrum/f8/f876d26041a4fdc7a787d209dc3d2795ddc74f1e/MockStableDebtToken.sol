// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {StableDebtToken} from "./tokenization_StableDebtToken.sol";
import {IPool} from "./IPool.sol";

contract MockStableDebtToken is StableDebtToken {
  constructor(IPool pool) StableDebtToken(pool) {}

  function getRevision() internal pure override returns (uint256) {
    return 0x3;
  }
}

