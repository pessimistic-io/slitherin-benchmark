pragma solidity ^0.8.18;

// SPDX-License-Identifier: MIT

import { GiantMevAndFeesPool } from "./GiantMevAndFeesPool.sol";
import { MockLSDNFactory } from "./MockLSDNFactory.sol";
import { IAccountManager } from "./IAccountManager.sol";

contract MockGiantMevAndFeesPool is GiantMevAndFeesPool {
    function getAccountManager() internal view override returns (IAccountManager accountManager) {
        return IAccountManager(MockLSDNFactory(address(liquidStakingDerivativeFactory)).accountMan());
    }
}
