// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import { ConfigStore } from "./ConfigStore.sol";
import { ConfigStoreInterfaces } from "./Constants.sol";
import { IContestFactory } from "./ContestFactory.sol";
import { ToggleGovernanceFactory } from "./ToggleGovernanceFactory.sol";

contract HasConfigStore {
    ConfigStore public immutable configStore;

    constructor(ConfigStore _configStore) {
        configStore = _configStore;
    }

    function _getContestFactory() internal view returns (IContestFactory) {
        return IContestFactory(configStore.getImplementationAddress(ConfigStoreInterfaces.CONTEST_FACTORY));
    }

    function _getToggleGovernorFactory() internal view returns (ToggleGovernanceFactory) {
        return // solhint-disable-next-line max-line-length
            ToggleGovernanceFactory(configStore.getImplementationAddress(ConfigStoreInterfaces.TOGGLE_GOVERNOR_FACTORY));
    }

    function _getBeneficiary() internal view returns (address) {
        return configStore.getImplementationAddress(ConfigStoreInterfaces.BENEFICIARY);
    }

    function _getTeamWallet() internal view returns (address) {
        return configStore.getImplementationAddress(ConfigStoreInterfaces.TEAM);
    }

    function _getTeamPercent() internal view returns (uint256) {
        return configStore.getImplementationUint256(ConfigStoreInterfaces.TEAM_PERCENT);
    }
}

