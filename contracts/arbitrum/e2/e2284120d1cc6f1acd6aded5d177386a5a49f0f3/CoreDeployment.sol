pragma solidity >=0.8.19;

// Core
import "./CoreProxy.sol";
import "./AssociatedSystemsModule.sol";

import "./OwnerUpgradeModule.sol";

/**
 * @title Core Deployment
 */
library CoreDeployment {
    /**
     * @dev Thrown when CoreRouter is missing
     */
    error MissingCoreRouter();
    /**
     * @dev Thrown when AccountNftRouter is missing
     */
    error MissingAccountNftRouter();

    struct Data {
        /// @notice Voltz Protocol V2 Core Router
        address coreRouter;

        /// @notice Voltz Protocol V2 Account NFT Router
        address accountNftRouter;

        /// @notice Id of Voltz Protocol V2 Account NFT as stored in the core proxy's associated system
        bytes32 accountNftId;

        /// @notice Name of Voltz Protocol V2 Account NFT
        string accountNftName;

        /// @notice Symbol of Voltz Protocol V2 Account NFT
        string accountNftSymbol;

        /// @notice Uri of Voltz Protocol V2 Account NFT
        string accountNftUri;
    }

    /**
     * @dev Loads the CoreDeploymentConfiguration object.
     * @return config The CoreDeploymentConfiguration object.
     */
    function load() internal pure returns (Data storage config) {
        bytes32 s = keccak256(abi.encode("xyz.voltz.CommunityCoreDeployment"));
        assembly {
            config.slot := s
        }
    }

    /**
     * @dev Sets the core deployment configuration
     * @param config The CoreDeploymentConfiguration object with all the parameters
     */
    function set(Data memory config) internal {
        Data storage storedConfig = load();
        if (config.coreRouter == address(0)) {
            revert MissingCoreRouter();
        }
        if (config.accountNftRouter == address(0)) {
            revert MissingAccountNftRouter();
        }
        storedConfig.coreRouter = config.coreRouter;
        storedConfig.accountNftRouter = config.accountNftRouter;
        storedConfig.accountNftId = config.accountNftId;
        storedConfig.accountNftName = config.accountNftName;
        storedConfig.accountNftSymbol = config.accountNftSymbol;
        storedConfig.accountNftUri = config.accountNftUri;
    }

    function deploy(address ownerAddress) internal returns (address coreProxy, address accountNftProxy) {
        Data storage config = load();

        coreProxy = address(new CoreProxy(config.coreRouter, address(this)));
        AssociatedSystemsModule(coreProxy).initOrUpgradeNft(
            config.accountNftId, config.accountNftName, config.accountNftSymbol, config.accountNftUri, config.accountNftRouter
        );
        OwnerUpgradeModule(coreProxy).nominateNewOwner(ownerAddress);

        (accountNftProxy, ) = AssociatedSystemsModule(coreProxy).getAssociatedSystem(config.accountNftId);
    }
}

