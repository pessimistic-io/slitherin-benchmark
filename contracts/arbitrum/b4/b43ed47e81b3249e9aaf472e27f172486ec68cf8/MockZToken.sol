// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {ZToken} from "./ZToken.sol";
import {ILendingPool} from "./ILendingPool.sol";
import {IZarbanIncentivesController} from "./IZarbanIncentivesController.sol";

contract MockZToken is ZToken {
  function getRevision() internal pure override returns (uint256) {
    return 0x2;
  }
}

