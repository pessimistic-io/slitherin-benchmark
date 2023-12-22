// SPDX-License-Identifier: MIT
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

import { IVaultStorage } from "./IVaultStorage.sol";
import { IGmxRewardRouterV2 } from "./IGmxRewardRouterV2.sol";
import { IGmxRewardTracker } from "./IGmxRewardTracker.sol";
import { IOracleMiddleware } from "./IOracleMiddleware.sol";
import { IGmxGlpManager } from "./IGmxGlpManager.sol";

interface IStakedGlpStrategy {
  struct StakedGlpStrategyConfig {
    IGmxRewardRouterV2 rewardRouter;
    IGmxRewardTracker rewardTracker;
    IGmxGlpManager glpManager;
    IOracleMiddleware oracleMiddleware;
    IVaultStorage vaultStorage;
  }

  function execute() external;

  function setWhiteListExecutor(address _executor, bool _active) external;
}

