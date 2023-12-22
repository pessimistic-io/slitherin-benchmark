pragma solidity >=0.8.19;

import "./Config.sol";

/**
 * @title Module for configuring the periphery
 * @notice Allows the owner to configure the periphery
 */
interface IConfigurationModule {
    /**
     * @notice Emitted when the periphery configuration is created or updated.
     * @param config The object with the newly configured details.
     */
    event PeripheryConfigured(Config.Data config);

    /**
     * @notice Creates or updates the configuration for the periphery
     * @param config The PeripheryConfiguration object describing the new configuration.
     *
     * Requirements:
     *
     * - `msg.sender` must be the owner of the system.
     *
     * Emits a {PeripheryConfigured} event.
     *
     */
    function configure(Config.Data memory config) external;

    /**
     * @notice Returns the periphery configuration object
     * @return config The configuration object of the periphery
     */
    function getConfiguration() external view returns (Config.Data memory config);
}

