pragma solidity >=0.8.19;

// Vamm
import "./VammProxy.sol";

import "./OwnerUpgradeModule.sol";

/**
 * @title Vamm Deployment
 */
library VammDeployment {
    /**
     * @dev Thrown when VammRouter is missing
     */
    error MissingVammRouter();

    struct Data {
        /// @notice Voltz Protocol V2 Vamm Router
        address vammRouter;
    }

    /**
     * @dev Loads the VammConfiguration object.
     * @return config The VammConfiguration object.
     */
    function load() internal pure returns (Data storage config) {
        bytes32 s = keccak256(abi.encode("xyz.voltz.CommunityVammDeployment"));
        assembly {
            config.slot := s
        }
    }

    /**
     * @dev Sets the vamm deployment configuration
     * @param config The VammDeploymentConfiguration object with all the parameters
     */
    function set(Data memory config) internal {
        Data storage storedConfig = load();
        if (config.vammRouter == address(0)) {
            revert MissingVammRouter();
        }
        storedConfig.vammRouter = config.vammRouter;
    }

    function deploy(address ownerAddress) internal returns (address vammProxy) {
        Data storage config = load();

        vammProxy = address(new VammProxy(config.vammRouter, address(this)));
        OwnerUpgradeModule(vammProxy).nominateNewOwner(ownerAddress);
    }
}

