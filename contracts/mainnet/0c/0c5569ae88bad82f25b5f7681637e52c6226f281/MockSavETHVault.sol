// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { IERC20 } from "./ERC20_IERC20.sol";
import { ISavETHManager } from "./ISavETHManager.sol";
import { IAccountManager } from "./IAccountManager.sol";
import { SavETHVault } from "./SavETHVault.sol";
import { LPTokenFactory } from "./LPTokenFactory.sol";
import { LiquidStakingManager } from "./LiquidStakingManager.sol";
import { MockSavETHRegistry } from "./MockSavETHRegistry.sol";
import { MockAccountManager } from "./MockAccountManager.sol";
import { IFactoryDependencyInjector } from "./IFactoryDependencyInjector.sol";
import { LPToken } from "./LPToken.sol";

contract MockSavETHVault is SavETHVault {

    MockSavETHRegistry public saveETHRegistry;
    MockAccountManager public accountMan;
    IERC20 public dETHToken;

    function injectDependencies(address _lsdnFactory) external {
        IFactoryDependencyInjector dependencyInjector = IFactoryDependencyInjector(
            _lsdnFactory
        );

        dETHToken = IERC20(dependencyInjector.dETH());
        saveETHRegistry = MockSavETHRegistry(dependencyInjector.saveETHRegistry());
        accountMan = MockAccountManager(dependencyInjector.accountMan());

        saveETHRegistry.setDETHToken(dETHToken);
    }

    function init(address _liquidStakingManagerAddress, LPTokenFactory _lpTokenFactory) external override {
        _init(_liquidStakingManagerAddress, _lpTokenFactory);
    }

    /// ----------------------
    /// Override Solidity API
    /// ----------------------

    function getSavETHRegistry() internal view override returns (ISavETHManager) {
        return ISavETHManager(address(saveETHRegistry));
    }

    function getAccountManager() internal view override returns (IAccountManager accountManager) {
        return IAccountManager(address(accountMan));
    }

    function getDETH() internal view override returns (IERC20 dETH) {
        return dETHToken;
    }
}
