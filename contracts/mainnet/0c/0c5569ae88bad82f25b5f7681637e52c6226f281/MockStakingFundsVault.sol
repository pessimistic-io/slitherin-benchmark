// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { IERC20 } from "./ERC20_IERC20.sol";
import { ISavETHManager } from "./ISavETHManager.sol";
import { IAccountManager } from "./IAccountManager.sol";

import { LiquidStakingManager } from "./LiquidStakingManager.sol";
import { LPTokenFactory } from "./LPTokenFactory.sol";
import { LPToken } from "./LPToken.sol";
import { StakingFundsVault } from "./StakingFundsVault.sol";
import { MockSavETHRegistry } from "./MockSavETHRegistry.sol";
import { MockAccountManager } from "./MockAccountManager.sol";
import { IFactoryDependencyInjector } from "./IFactoryDependencyInjector.sol";

contract MockStakingFundsVault is StakingFundsVault {

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

    function init(address _liquidStakingManagerAddress, LPTokenFactory _tokenFactory) external override {
        _init(LiquidStakingManager(payable(_liquidStakingManagerAddress)), _tokenFactory);
    }

    /// ----------------------
    /// Override Solidity API
    /// ----------------------

    function getAccountManager() internal view override returns (IAccountManager accountManager) {
        return IAccountManager(address(accountMan));
    }

}
