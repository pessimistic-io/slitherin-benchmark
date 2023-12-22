// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IERC20} from "./BalancerFlashloan.sol";
import {IOrangeParametersV1} from "./IOrangeParametersV1.sol";
import {IOrangeStorageV1} from "./IOrangeStorageV1.sol";
import {OrangeERC20, IERC20Decimals} from "./OrangeERC20.sol";

abstract contract OrangeStorageV1 is IOrangeStorageV1, OrangeERC20 {
    struct DepositType {
        uint256 assets;
        uint40 timestamp;
    }

    //OrangeVault
    int24 public lowerTick;
    int24 public upperTick;
    bool public hasPosition;
    bytes32 public flashloanHash; //cache flashloan hash to check validity

    /* ========== PARAMETERS ========== */
    address public liquidityPool;
    address public lendingPool;
    IERC20 public token0; //collateral and deposited currency by users
    IERC20 public token1; //debt and hedge target token
    IOrangeParametersV1 public params;
    address public router;
    uint24 public routerFee;
    address public balancer;

    function decimals() public view override returns (uint8) {
        return IERC20Decimals(address(token0)).decimals();
    }
}

