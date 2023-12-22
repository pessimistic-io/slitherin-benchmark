// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Claims} from "./Claims.sol";

interface IReclaim {
    struct Witness {
        address addr;
        string host;
    }

    struct Epoch {
        uint32 id;
        uint32 timestampStart;
        uint32 timestampEnd;
        Witness[] witnesses;
        uint8 minimumWitnessesForClaimCreation;
    }

    struct Proof {
        Claims.ClaimInfo claimInfo;
        Claims.SignedClaim signedClaim;
    }

    event EpochAdded(Epoch epoch);
    event GroupCreated(uint256 indexed groupId, string indexed provider);
    event DappCreated(bytes32 indexed dappId);

    function initialize(address _semaphoreAddress) external;

    function _authorizeUpgrade(address newImplementation) external view;

    function fetchEpoch(uint32 epoch) external view returns (Epoch memory);

    function fetchWitnessesForClaim(
        uint32 epoch,
        bytes32 identifier,
        uint32 timestampS
    ) external view returns (Witness[] memory);

    function createDapp(uint256 id) external;

    function getProviderFromProof(
        Proof memory proof
    ) external pure returns (string memory);

    function getContextMessageFromProof(
        Proof memory proof
    ) external pure returns (string memory);

    function getContextAddressFromProof(
        Proof memory proof
    ) external pure returns (string memory);

    function getMerkelizedUserParams(
        string memory provider,
        string memory params
    ) external view returns (bool);

    function verifyProof(Proof memory proof) external returns (bool);

    function createGroup(
        string memory provider,
        uint256 merkleTreeDepth
    ) external;

    function merkelizeUser(
        Proof memory proof,
        uint256 _identityCommitment
    ) external;

    function verifyMerkelIdentity(
        string memory provider,
        uint256 _merkleTreeRoot,
        uint256 _signal,
        uint256 _nullifierHash,
        uint256 _externalNullifier,
        bytes32 dappId,
        uint256[8] calldata _proof
    ) external returns (bool);

    function addNewEpoch(
        Witness[] calldata witnesses,
        uint8 requisiteWitnessesForClaimCreate
    ) external;
}

