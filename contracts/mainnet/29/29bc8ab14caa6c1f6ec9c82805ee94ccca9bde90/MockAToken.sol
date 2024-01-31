// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {AToken} from "./AToken.sol";
import {IL1Pool} from "./IL1Pool.sol";
import {IFintochIncentivesController} from "./IFintochIncentivesController.sol";

contract MockAToken is AToken {
  constructor(IL1Pool pool) AToken(pool) {}

  function getRevision() internal pure override returns (uint256) {
    return 0x2;
  }
}

