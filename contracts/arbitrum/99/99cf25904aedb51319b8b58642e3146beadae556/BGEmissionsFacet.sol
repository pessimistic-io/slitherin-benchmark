// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

// Library imports
import { LibEmissionsUtils } from "./LibEmissionsUtils.sol";

// Contract imports
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

contract BGEmissionsFacet is WithModifiers, ReentrancyGuard {
    event ClaimedRNG(address account, uint256 claimableMagic, uint256 epoch);
    event MerkleRootSet(bytes32 root, uint256 emissionsEpoch);
    event MagicRNGEmissionsDeposited(address account, uint256 epoch, uint256 amount);
    event ProcessingEpochRolledOver(uint256 processingEpoch);

    function rollOverProcessingEpoch() external notPaused onlyBackendExecutor {
        LibEmissionsUtils.rollOverProcessingEpoch();
    }

    function depositMagicRNGEmissions(
        uint256 depositAmountInWei,
        uint256 gameAmountInWei
    ) external notPaused onlyEmissionDepositor {
        LibEmissionsUtils.depositMagicRNGEmissions(depositAmountInWei, gameAmountInWei);
    }

    /**
     * @dev Claims outstanding Battlefly Game emissions.
     */
    function claimEmissions(
        uint256 index,
        uint256 epoch,
        bytes calldata data,
        bytes32[] calldata merkleProof
    ) external nonReentrant notPaused {
        LibEmissionsUtils.claimEmissions(index, epoch, data, merkleProof);
    }

    /**
     * @dev Set the merkle root and increase the emissions epoch
     */
    function setMerkleRoot(bytes32 root) external notPaused onlyBackendExecutor {
        LibEmissionsUtils.setMerkleRoot(root);
    }

    /**
     * @dev Get the claimable RNG Magic emissions for an account
     */
    function getClaimableMagicRNGEmissionsFor(address account, bytes calldata data) external view returns (uint256) {
        return LibEmissionsUtils.getClaimableMagicRNGEmissionsFor(account, data);
    }

    /**
     * @dev Get the amount of Magic RNG emissions claimed for an account
     */
    function getClaimedMagicRNGEmissionsFor(address account) external view returns (uint256) {
        return LibEmissionsUtils.getClaimedMagicRNGEmissionsFor(account);
    }

    /**
     * @dev Get the currently active Merkleroot
     */
    function getMerkleRoot() external view returns (bytes32) {
        return LibEmissionsUtils.getMerkleRoot();
    }

    /**
     * @dev Get the currently active emissions epoch
     */
    function getEmissionsEpoch() external view returns (uint256) {
        return LibEmissionsUtils.getEmissionsEpoch();
    }

    /**
     * @dev Get the currently active processing epoch
     */
    function getProcessingEpoch() external view returns (uint256) {
        return LibEmissionsUtils.getProcessingEpoch();
    }
}

