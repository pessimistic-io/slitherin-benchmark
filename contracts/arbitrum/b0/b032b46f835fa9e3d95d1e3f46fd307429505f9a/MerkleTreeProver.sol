//SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ========================= MerkleTreeProver =========================
// ====================================================================
// Frax Finance: https://github.com/FraxFinance

// Authors
// Jon Walch: https://github.com/jonwalch
// Dennis: https://github.com/denett

// Reviewers
// Drake Evans: https://github.com/DrakeEvans

// ====================================================================
import { RLPReader } from "./RLPReader.sol";
import { StateProofVerifier as Verifier } from "./StateProofVerifier.sol";

/// @title MerkleTreeProver
/// @author Jon Walch (Frax Finance) https://github.com/jonwalch
/// @notice Helper function library for interacting with StateProofVerifier and RLPReader
library MerkleTreeProver {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    /// @notice The ```proveStorageRoot``` function is a helper function for StateProofVerifier.extractAccountFromProof()
    /// @param stateRootHash The hash of the state root
    /// @param proofAddress The address of the contract we're proving
    /// @param accountProof The accountProof retrieved from eth_getProof
    function proveStorageRoot(
        bytes32 stateRootHash,
        address proofAddress,
        bytes[] memory accountProof
    ) internal view returns (Verifier.Account memory accountPool) {
        RLPReader.RLPItem[] memory accountProofRlp = new RLPReader.RLPItem[](accountProof.length);
        for (uint256 i = 0; i < accountProof.length; ++i) {
            accountProofRlp[i] = accountProof[i].toRlpItem();
        }
        accountPool = Verifier.extractAccountFromProof({
            _addressHash: keccak256(abi.encodePacked(proofAddress)),
            _stateRootHash: stateRootHash,
            _proof: accountProofRlp
        });
    }

    /// @notice The ```proveStorageSlotValue``` function is a helper function for StateProofVerifier.extractSlotValueFromProof()
    /// @param storageRootHash The hash of the storage root
    /// @param slot The slot we want to prove for the contract
    /// @param storageProof The storageProof.proof retrieved from eth_getProof
    function proveStorageSlotValue(
        bytes32 storageRootHash,
        bytes32 slot,
        bytes[] memory storageProof
    ) internal view returns (Verifier.SlotValue memory slotValue) {
        RLPReader.RLPItem[] memory storageProofRlp = new RLPReader.RLPItem[](storageProof.length);
        for (uint256 i = 0; i < storageProof.length; ++i) {
            storageProofRlp[i] = storageProof[i].toRlpItem();
        }
        slotValue = Verifier.extractSlotValueFromProof({
            _slotHash: keccak256(abi.encodePacked(slot)),
            _storageRootHash: storageRootHash,
            _proof: storageProofRlp
        });
    }
}

