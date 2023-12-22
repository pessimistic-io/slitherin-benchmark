pragma solidity >=0.8.19;

import "./IConfigurationModule.sol";
import "./Config.sol";
import "./OwnableStorage.sol";

/**
 * @title Module for configuring the periphery
 * @dev See IConfigurationModule.
 */
contract ConfigurationModule is IConfigurationModule {
    using Config for Config.Data;

    /**
     * @inheritdoc IConfigurationModule
     */
    function configure(Config.Data memory config) external override {
        OwnableStorage.onlyOwner();

        Config.set(config);

        emit PeripheryConfigured(config);
    }

    /**
     * @inheritdoc IConfigurationModule
     */
    function getConfiguration() external pure override returns (Config.Data memory) {
        return Config.load();
    }
}

