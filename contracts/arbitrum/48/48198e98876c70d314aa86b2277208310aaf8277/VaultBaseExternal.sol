// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Registry } from "./Registry.sol";
import { IGmxPositionRouterCallbackReceiver } from "./IGmxPositionRouterCallbackReceiver.sol";
import { VaultBaseInternal } from "./VaultBaseInternal.sol";
import { ExecutorIntegration } from "./IExecutor.sol";
import { VaultBaseStorage } from "./VaultBaseStorage.sol";

import "./console.sol";

contract VaultBaseExternal is
    IGmxPositionRouterCallbackReceiver,
    VaultBaseInternal
{
    function registry() external view returns (Registry) {
        return _registry();
    }

    function manager() external view returns (address) {
        return _manager();
    }

    function enabledAssets(address asset) public view returns (bool) {
        VaultBaseStorage.Layout storage l = VaultBaseStorage.layout();
        return l.enabledAssets[asset];
    }

    // The Executor runs as the Vault. I'm not sure this is ideal but it makes writing executors easy
    // Other solutions are
    // 1. The executor returns transactions to be executed which are then assembly called by the this
    // 2. We write the executor code in the vault
    function execute(
        ExecutorIntegration integration,
        bytes memory encodedWithSelectorPayload
    ) external payable onlyManager {
        _execute(integration, encodedWithSelectorPayload);
    }

    function gmxPositionCallback(
        bytes32 positionKey,
        bool isExecuted,
        bool isIncrease
    ) external {
        _gmxPositionCallback(positionKey, isExecuted, isIncrease);
    }

    function assetsWithBalances() public view returns (address[] memory) {
        VaultBaseStorage.Layout storage l = VaultBaseStorage.layout();
        return l.assets;
    }

    function addActiveAsset(address asset) public onlyThis {
        _addAsset(asset);
    }

    function updateActiveAsset(address asset) public onlyThis {
        _updateActiveAsset(asset);
    }

    function receiveBridgedAsset(address asset) external onlyTransport {
        _updateActiveAsset(asset);
    }
}

