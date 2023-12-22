// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {ViToken} from "./ViToken.sol";
import {ILendingPool} from "./ILendingPool.sol";
import {IViniumIncentivesController} from "./IViniumIncentivesController.sol";

contract MockViToken is ViToken {
  function getRevision() internal pure override returns (uint256) {
    return 0x2;
  }
}

