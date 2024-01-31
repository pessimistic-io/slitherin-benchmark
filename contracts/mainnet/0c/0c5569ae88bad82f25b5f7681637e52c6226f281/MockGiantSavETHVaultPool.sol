pragma solidity ^0.8.18;

// SPDX-License-Identifier: MIT

import { IERC20 } from "./ERC20_IERC20.sol";

import { GiantSavETHVaultPool } from "./GiantSavETHVaultPool.sol";
import { GiantLP } from "./GiantLP.sol";
import { LSDNFactory } from "./LSDNFactory.sol";
import { MockLSDNFactory } from "./MockLSDNFactory.sol";

contract MockGiantSavETHVaultPool is GiantSavETHVaultPool {

    /// ----------------------
    /// Override Solidity API
    /// ----------------------

    function getDETH() internal view override returns (IERC20 dETH) {
        return IERC20(MockLSDNFactory(address(liquidStakingDerivativeFactory)).dETH());
    }
}
