// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { LiquidStakingManager } from "./LiquidStakingManager.sol";
import { LPTokenFactory } from "./LPTokenFactory.sol";
import { LSDNFactory } from "./LSDNFactory.sol";
import { MockSavETHVault } from "./MockSavETHVault.sol";
import { MockStakingFundsVault } from "./MockStakingFundsVault.sol";
import { SyndicateFactory } from "./SyndicateFactory.sol";
import { Syndicate } from "./Syndicate.sol";
import { MockAccountManager } from "./MockAccountManager.sol";
import { MockTransactionRouter } from "./MockTransactionRouter.sol";
import { MockStakeHouseUniverse } from "./MockStakeHouseUniverse.sol";
import { MockSlotRegistry } from "./MockSlotRegistry.sol";
import { IAccountManager } from "./IAccountManager.sol";
import { ITransactionRouter } from "./ITransactionRouter.sol";
import { IStakeHouseUniverse } from "./IStakeHouseUniverse.sol";
import { ISlotSettlementRegistry } from "./ISlotSettlementRegistry.sol";

import { IFactoryDependencyInjector } from "./IFactoryDependencyInjector.sol";

contract MockLiquidStakingManagerV2 is LiquidStakingManager {

    /// @dev Mock stakehouse dependencies injected from the super factory
    address public accountMan;
    address public txRouter;
    address public uni;
    address public slot;

    function sing() external view returns (bool) {
        return true;
    }
}
