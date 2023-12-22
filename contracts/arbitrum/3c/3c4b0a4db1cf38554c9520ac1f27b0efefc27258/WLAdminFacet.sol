// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DiamondOwnable } from "./DiamondOwnable.sol";
import { DiamondAccessControl } from "./DiamondAccessControl.sol";

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";
import { ERC721MetadataStorage } from "./ERC721MetadataStorage.sol";

// Library imports
import { LibLandUtils } from "./LibLandUtils.sol";

contract WLAdminFacet is WithModifiers, DiamondAccessControl {
    using ERC721MetadataStorage for ERC721MetadataStorage.Layout;

    event PauseStateChanged(bool paused);
    event MintMerkleRootSet(bytes32 mintMerkleRoot);
    event LandMetadataURIAndExtensionSet(string metadataUri, string metadataExtension);
    event ContractURISet(string landContractURI);

    /**
     * @dev Pause the contract
     */
    function pause() external onlyGuardian notPaused {
        ws().paused = true;
        emit PauseStateChanged(true);
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyGuardian {
        if (!ws().paused) revert Errors.WastelandsAlreadyUnPaused();
        ws().paused = false;
        emit PauseStateChanged(false);
    }

    /**
     * @dev Set the merkle root for minting
     */
    function setMintMerkleRoot(bytes32 mintMerkleRoot) external onlyOwner {
        ws().mintMerkleRoot = mintMerkleRoot;
        emit MintMerkleRootSet(mintMerkleRoot);
    }

    /**
     * @dev Set the Wastelands metadata URI and extension
     */
    function setLandMetadataURIAndExtension(
        string calldata metadataUri,
        string calldata metadataExtension
    ) external onlyOwner {
        ERC721MetadataStorage.layout().baseURI = metadataUri;
        ws().landMetadataExtension = metadataExtension;
        emit LandMetadataURIAndExtensionSet(metadataUri, metadataExtension);
    }

    /**
     * @dev Set the wastelands contract URI
     */
    function setLandContractURI(string calldata landContractURI) external onlyOwner {
        ws().landContractURI = landContractURI;
        emit ContractURISet(landContractURI);
    }
}

