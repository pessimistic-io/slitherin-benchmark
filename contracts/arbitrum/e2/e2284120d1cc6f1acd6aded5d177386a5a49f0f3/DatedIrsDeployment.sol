pragma solidity >=0.8.19;

// Dated IRS
import "./ProductProxy.sol";

import "./OwnerUpgradeModule.sol";

/**
 * @title DatedIrs Deployment
 */
library DatedIrsDeployment {
    /**
     * @dev Thrown when DatedIrsRouter is missing
     */
    error MissingDatedIrsRouter();

    struct Data {
        /// @notice Voltz Protocol V2 Dated IRS Router
        address datedIrsRouter;
    }

    /**
     * @dev Loads the DatedIrsConfiguration object.
     * @return config The DatedIrsConfiguration object.
     */
    function load() internal pure returns (Data storage config) {
        bytes32 s = keccak256(abi.encode("xyz.voltz.CommunityDatedIrsDeployment"));
        assembly {
            config.slot := s
        }
    }

    /**
     * @dev Sets the dated irs deployment configuration
     * @param config The DatedIrsDeploymentConfiguration object with all the parameters
     */
    function set(Data memory config) internal {
        Data storage storedConfig = load();
        if (config.datedIrsRouter == address(0)) {
            revert MissingDatedIrsRouter();
        }
        storedConfig.datedIrsRouter = config.datedIrsRouter;
    }

    function deploy(address ownerAddress) internal returns (address datedIrsProxy) {
        Data storage config = load();

        datedIrsProxy = address(new ProductProxy(config.datedIrsRouter, address(this)));
        OwnerUpgradeModule(datedIrsProxy).nominateNewOwner(ownerAddress);
    }
}

