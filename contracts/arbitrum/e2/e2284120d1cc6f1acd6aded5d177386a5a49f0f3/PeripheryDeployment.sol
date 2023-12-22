pragma solidity >=0.8.19;

// Periphery
import "./PeripheryProxy.sol";

import "./OwnerUpgradeModule.sol";

/**
 * @title Periphery Deployment
 */
library PeripheryDeployment {
    /**
     * @dev Thrown when PeripheryRouter is missing
     */
    error MissingPeripheryRouter();

    struct Data {
        /// @notice Voltz Protocol V2 Periphery Router
        address peripheryRouter;
    }

    /**
     * @dev Loads the PeripheryConfiguration object.
     * @return config The PeripheryConfiguration object.
     */
    function load() internal pure returns (Data storage config) {
        bytes32 s = keccak256(abi.encode("xyz.voltz.CommunityPeripheryDeployment"));
        assembly {
            config.slot := s
        }
    }

    /**
     * @dev Sets the periphery deployment configuration
     * @param config The PeripheryDeploymentConfiguration object with all the parameters
     */
    function set(Data memory config) internal {
        Data storage storedConfig = load();
        if (config.peripheryRouter == address(0)) {
            revert MissingPeripheryRouter();
        }
        storedConfig.peripheryRouter = config.peripheryRouter;
    }

    function deploy(address ownerAddress) internal returns (address peripheryProxy) {
        Data storage config = load();

        peripheryProxy = address(new PeripheryProxy(config.peripheryRouter, address(this)));
        OwnerUpgradeModule(peripheryProxy).nominateNewOwner(ownerAddress);
    }
}

