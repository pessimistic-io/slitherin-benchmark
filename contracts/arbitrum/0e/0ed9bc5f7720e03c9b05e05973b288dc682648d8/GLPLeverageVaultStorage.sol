// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./ERC20_IERC20Upgradeable.sol";
import "./IRewardRouterV2.sol";
import "./IWrappedGLP.sol";
import "./ILendingPool.sol";
import "./ISwapRouter.sol";
import "./IStrategy.sol";

contract GLPLeverageVaultStorage {
    IERC20Upgradeable public sGLP;
    IStrategy public strategy;
}

