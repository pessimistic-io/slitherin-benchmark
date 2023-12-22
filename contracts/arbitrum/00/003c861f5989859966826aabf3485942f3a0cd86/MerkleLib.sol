// SPDX-License-Identifier: LGPL-3.0-only
// Created By: Art Blocks Inc.

pragma solidity ^0.8.0;

import {GenericMinterEventsLib} from "./GenericMinterEventsLib.sol";

import {MerkleProof} from "./MerkleProof.sol";

/**
 * @title Art Blocks Merkle Library
 * @notice This library is designed to manage and verify merkle based gating for Art Blocks projects.
 * It provides functionalities such as updating the merkle root of project, verifying an address against a proof,
 * and setting the maximum number of invocations per address for a project.
 * @author Art Blocks Inc.
 */

library MerkleLib {
    using MerkleProof for bytes32[];

    /// Events specific to this library ///
    /**
     * @notice Notifies of the contract's default maximum mints allowed per
     * user for a given project, on this minter. This value can be overridden
     * by the artist of any project at any time.
     * @param defaultMaxInvocationsPerAddress The default maximum mints allowed
     */
    event DefaultMaxInvocationsPerAddress(
        uint256 defaultMaxInvocationsPerAddress
    );
    /**
     * @notice Notifies of the contracts' current delegation registry address.
     * @param delegationRegistry The address of the delegation registry
     */
    event DelegationRegistryUpdated(address delegationRegistry);

    // position of Merkle Lib storage, using a diamond storage pattern for this
    // library
    bytes32 constant MERKLE_LIB_STORAGE_POSITION =
        keccak256("merklelib.storage");

    /// @notice Default maximum invocations per address
    uint256 internal constant DEFAULT_MAX_INVOCATIONS_PER_ADDRESS = 1;
    bytes32 internal constant CONFIG_MERKLE_ROOT = "merkleRoot";
    bytes32 internal constant CONFIG_USE_MAX_INVOCATIONS_PER_ADDRESS_OVERRIDE =
        "useMaxMintsPerAddrOverride"; // shortened to fit in 32 bytes
    bytes32 internal constant CONFIG_MAX_INVOCATIONS_OVERRIDE =
        "maxMintsPerAddrOverride"; // shortened to match format of previous key

    struct MerkleProjectConfig {
        // If true, the maxInvocationsPerAddressOverride will be used.
        // If false, the default max invocations per address will be used.
        bool useMaxInvocationsPerAddressOverride;
        // Maximum invocations allowed per address.
        // This will be used if useMaxInvocationsPerAddressOverride is true.
        // A value of 0 means no limit.
        // @dev Safe to use uint24 because maxInvocationsPerAddressOverride <= 1_000_000
        // and 1_000_000 << max uint24
        uint24 maxInvocationsPerAddressOverride;
        // The root of the Merkle tree for this project.
        bytes32 merkleRoot;
        // The number of current invocations for this project from a given user address.
        mapping(address user => uint256 mintInvocations) userMintInvocations;
    }

    // Diamond storage pattern is used in this library
    struct MerkleLibStorage {
        mapping(address coreContract => mapping(uint256 projectId => MerkleProjectConfig)) merkleProjectConfigs;
    }

    /**
     * @notice Sets the maximum number of invocations per address for a project.
     * @param projectId The ID of the project to set the maximum invocations for.
     * @param coreContract The address of the core contract.
     * @param maxInvocationsPerAddress The maximum number of invocations per address.
     */
    function setProjectInvocationsPerAddress(
        uint256 projectId,
        address coreContract,
        uint24 maxInvocationsPerAddress
    ) internal {
        MerkleProjectConfig
            storage merkleProjectConfig = getMerkleProjectConfig({
                projectId: projectId,
                coreContract: coreContract
            });
        merkleProjectConfig.useMaxInvocationsPerAddressOverride = true;
        merkleProjectConfig
            .maxInvocationsPerAddressOverride = maxInvocationsPerAddress;
        emit GenericMinterEventsLib.ConfigValueSet({
            projectId: projectId,
            coreContract: coreContract,
            key: CONFIG_USE_MAX_INVOCATIONS_PER_ADDRESS_OVERRIDE,
            value: true
        });
        emit GenericMinterEventsLib.ConfigValueSet({
            projectId: projectId,
            coreContract: coreContract,
            key: CONFIG_MAX_INVOCATIONS_OVERRIDE,
            value: uint256(maxInvocationsPerAddress)
        });
    }

    /**
     * @notice Updates the Merkle root of a project.
     * @param projectId The ID of the project to update.
     * @param coreContract The address of the core contract.
     * @param root The new Merkle root.
     */
    function updateMerkleRoot(
        uint256 projectId,
        address coreContract,
        bytes32 root
    ) internal {
        require(root != bytes32(0), "Root must be provided");
        MerkleProjectConfig
            storage merkleProjectConfig = getMerkleProjectConfig({
                projectId: projectId,
                coreContract: coreContract
            });
        merkleProjectConfig.merkleRoot = root;
        emit GenericMinterEventsLib.ConfigValueSet({
            projectId: projectId,
            coreContract: coreContract,
            key: CONFIG_MERKLE_ROOT,
            value: root
        });
    }

    /**
     * @notice Checks that a given proof is valid for the vault address, and
     * also checks that the vault address has not exceeded the maximum number
     * of invocations per address for the project.
     * @dev Reverts if the proof is invalid or if the vault address has
     * exceeded the maximum number of invocations per address for the project.
     * @param projectId project id to check
     * @param coreContract core contract address to check
     * @param proof Merkle proof to check
     * @param vault address to check proof against
     */
    function preMintChecks(
        uint256 projectId,
        address coreContract,
        bytes32[] calldata proof,
        address vault
    ) internal view {
        MerkleProjectConfig
            storage merkleProjectConfig = getMerkleProjectConfig({
                projectId: projectId,
                coreContract: coreContract
            });
        // require valid Merkle proof
        require(
            _verifyAddress({
                proofRoot: merkleProjectConfig.merkleRoot,
                proof: proof,
                address_: vault
            }),
            "Invalid Merkle proof"
        );

        // limit mints per address by project
        uint256 maxProjectInvocationsPerAddress = projectMaxInvocationsPerAddress(
                merkleProjectConfig
            );

        // note that mint limits index off of the `vault` (when applicable)
        require(
            merkleProjectConfig.userMintInvocations[vault] <
                maxProjectInvocationsPerAddress ||
                maxProjectInvocationsPerAddress == 0,
            "Max invocations reached"
        );
    }

    /**
     * @notice Updates the number of invocations for the `vault` address on the
     * given project.
     * @param projectId Project Id to mint on
     * @param coreContract Core contract address to mint on
     * @param vault Address being used to mint (the allowlisted address)
     */
    function mintEffects(
        uint256 projectId,
        address coreContract,
        address vault
    ) internal {
        MerkleProjectConfig
            storage merkleProjectConfig = getMerkleProjectConfig({
                projectId: projectId,
                coreContract: coreContract
            });
        // increment mint invocations for vault address
        unchecked {
            // this will never overflow since user's invocations on a project
            // are limited by the project's max invocations
            merkleProjectConfig.userMintInvocations[vault]++;
        }
    }

    /**
     * @notice Hashes an address.
     * @param address_ The address to hash.
     * @return The hash of the address.
     */
    function hashAddress(address address_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(address_));
    }

    /**
     * @notice Processes a proof for an address.
     * @param proof The proof to process.
     * @param address_ The address to process the proof for.
     * @return The resulting hash from processing the proof.
     */
    function processProofForAddress(
        bytes32[] calldata proof,
        address address_
    ) internal pure returns (bytes32) {
        return proof.processProofCalldata(hashAddress(address_));
    }

    /**
     * @notice Returns the maximum number of invocations per address for a project.
     * @param projectConfig The merkle project config to check.
     * @return The maximum number of invocations per address.
     */
    function projectMaxInvocationsPerAddress(
        MerkleProjectConfig storage projectConfig
    ) internal view returns (uint256) {
        if (projectConfig.useMaxInvocationsPerAddressOverride) {
            return uint256(projectConfig.maxInvocationsPerAddressOverride);
        } else {
            return DEFAULT_MAX_INVOCATIONS_PER_ADDRESS;
        }
    }

    /**
     * @notice Returns the maximum number of invocations per address for a project.
     * @param projectId Project Id to get config for
     * @param coreContract Core contract address to get config for
     * @return The maximum number of invocations per address.
     */
    function projectMaxInvocationsPerAddress(
        uint256 projectId,
        address coreContract
    ) internal view returns (uint256) {
        MerkleProjectConfig storage projectConfig = getMerkleProjectConfig({
            projectId: projectId,
            coreContract: coreContract
        });
        return projectMaxInvocationsPerAddress(projectConfig);
    }

    /**
     * @notice Returns the number of invocations for a given address on a given
     * project.
     * @param projectId Project Id to query
     * @param coreContract Core contract address to query
     * @param purchaser Address to query
     */
    function projectUserMintInvocations(
        uint256 projectId,
        address coreContract,
        address purchaser
    ) internal view returns (uint256) {
        MerkleProjectConfig storage projectConfig = getMerkleProjectConfig({
            projectId: projectId,
            coreContract: coreContract
        });
        return projectConfig.userMintInvocations[purchaser];
    }

    /**
     * @notice Returns remaining invocations for a given address.
     * If `projectLimitsMintInvocationsPerAddress` is false, individual
     * addresses are only limited by the project's maximum invocations, and a
     * dummy value of zero is returned for `mintInvocationsRemaining`.
     * If `projectLimitsMintInvocationsPerAddress` is true, the quantity of
     * remaining mint invocations for address `address` is returned as
     * `mintInvocationsRemaining`.
     * Note that mint invocations per address can be changed at any time by the
     * artist of a project.
     * Also note that all mint invocations are limited by a project's maximum
     * invocations as defined on the core contract. This function may return
     * a value greater than the project's remaining invocations.
     * @param projectId Project Id to get remaining invocations on
     * @param coreContract Core contract address of project
     * @param address_ Address to get remaining invocations for
     * @return projectLimitsMintInvocationsPerAddress If true, the project
     * limits mint invocations per address. If false, the project does not
     * limit mint invocations per address.
     * @return mintInvocationsRemaining The number of remaining mint invocations
     * for address `address_`. If `projectLimitsMintInvocationsPerAddress` is
     * false, this value is always dummy zero.
     */
    function projectRemainingInvocationsForAddress(
        uint256 projectId,
        address coreContract,
        address address_
    )
        internal
        view
        returns (
            bool projectLimitsMintInvocationsPerAddress,
            uint256 mintInvocationsRemaining
        )
    {
        MerkleProjectConfig storage projectConfig = getMerkleProjectConfig({
            projectId: projectId,
            coreContract: coreContract
        });
        uint256 maxInvocationsPerAddress = projectMaxInvocationsPerAddress(
            projectConfig
        );
        if (maxInvocationsPerAddress != 0) {
            projectLimitsMintInvocationsPerAddress = true;
            uint256 userMintInvocations = projectConfig.userMintInvocations[
                address_
            ];
            // if user has not reached max invocations per address, return
            // remaining invocations
            if (maxInvocationsPerAddress > userMintInvocations) {
                unchecked {
                    // will never underflow due to the check above
                    mintInvocationsRemaining =
                        maxInvocationsPerAddress -
                        userMintInvocations;
                }
            }
            // else user has reached their maximum invocations, so leave
            // `mintInvocationsRemaining` at solidity initial value of zero
        }
        // else maxInvocationsPerAddress is zero, then the project does not
        // limit mint invocations per address, so do nothing. Leave
        // `projectLimitsMintInvocationsPerAddress` at solidity initial
        // value of false. Also leave `mintInvocationsRemaining` at
        // solidity initial value of zero, as indicated in this function's
        // documentation.
    }

    /**
     * Loads the MerkleProjectConfig for a given project and core contract.
     * @param projectId Project Id to get config for
     * @param coreContract Core contract address to get config for
     */
    function getMerkleProjectConfig(
        uint256 projectId,
        address coreContract
    ) internal view returns (MerkleProjectConfig storage) {
        return s().merkleProjectConfigs[coreContract][projectId];
    }

    /**
     * @notice Return the storage struct for reading and writing. This library
     * uses a diamond storage pattern when managing storage.
     * @return storageStruct The MerkleLibStorage struct.
     */
    function s()
        internal
        pure
        returns (MerkleLibStorage storage storageStruct)
    {
        bytes32 position = MERKLE_LIB_STORAGE_POSITION;
        assembly ("memory-safe") {
            storageStruct.slot := position
        }
    }

    /**
     * @notice Verifies an address against a proof.
     * @param proofRoot The root of the proof to verify agaisnst.
     * @param proof The proof to verify.
     * @param address_ The address to verify.
     * @return True if the address is verified, false otherwise.
     */
    function _verifyAddress(
        bytes32 proofRoot,
        bytes32[] calldata proof,
        address address_
    ) private pure returns (bool) {
        return
            proof.verifyCalldata({
                root: proofRoot,
                leaf: hashAddress(address_)
            });
    }
}

