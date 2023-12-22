// (c) 2023 Primex.finance
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";

import {IBucket} from "./IBucket.sol";
import {IFeeExecutor} from "./IFeeExecutor.sol";
import {IActivityRewardDistributor} from "./IActivityRewardDistributor.sol";

interface IDebtTokenStorage is IERC20Upgradeable {
    function bucket() external view returns (IBucket);

    function feeDecreaser() external view returns (IFeeExecutor);

    function traderRewardDistributor() external view returns (IActivityRewardDistributor);
}

