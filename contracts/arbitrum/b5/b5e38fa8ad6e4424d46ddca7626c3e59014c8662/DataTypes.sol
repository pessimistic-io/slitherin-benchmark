// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { EnumerableSet } from "./EnumerableSet.sol";

/// @dev DataTypes.sol defines the PerpetualMint struct data types used in the PerpetualMintStorage layout

/// @dev Represents data specific to a collection
struct CollectionData {
    /// @dev keeps track of mint requests which have not yet been fulfilled
    /// @dev used to implement the collection risk & collection mint multiplier update "state-machine" check
    EnumerableSet.UintSet pendingRequests;
    /// @dev price of mint attempt in ETH (native token) for a collection
    uint256 mintPrice;
    /// @dev risk of ruin for a collection
    uint32 risk;
    /// @dev mint fee distribution ratio for a collection in basis points
    uint32 mintFeeDistributionRatioBP;
    /// @dev mint consolation multiplier for a collection
    uint256 mintMultiplier;
}

/// @dev Represents the outcome of a single mint attempt.
struct MintOutcome {
    /// @dev The index of the tier in which the outcome falls under
    uint256 tierIndex;
    /// @dev The multiplier of the tier, scaled by BASIS
    uint256 tierMultiplier;
    /// @dev The risk or probability of landing in this tier, scaled by BASIS
    uint256 tierRisk;
    /// @dev The amount of $MINT to be issued if this outcome is hit, in units of wei
    uint256 mintAmount;
}

/// @dev Represents the total result of a batch mint attempt.
struct MintResultData {
    /// @dev An array containing the outcomes of each individual mint attempt
    MintOutcome[] mintOutcomes;
    /// @dev The total amount of $MINT to be issued based on all outcomes, in units of wei
    uint256 totalMintAmount;
    /// @dev The total number of successful mint attempts where a prize ticket was awarded
    uint256 totalSuccessfulMints;
}

/// @dev Represents data specific to $MINT mint for $MINT consolation tiers
struct MintTokenTiersData {
    /// @dev assumed ordered array of risks for each tier
    uint32[] tierRisks;
    /// @dev assumed ordered array of $MINT consolation multipliers for each tier
    uint256[] tierMultipliers;
}

/// @dev Represents data specific to mint requests
/// @dev Updated as a new request is made and removed when the request is fulfilled
struct RequestData {
    /// @dev address of collection for mint attempt
    address collection;
    /// @dev address of minter who made the request
    address minter;
}

/// @dev Represents data specific to $MINT mint for collection consolation tiers
struct TiersData {
    /// @dev assumed ordered array of risks for each tier
    uint32[] tierRisks;
    /// @dev assumed ordered array of $MINT consolation multipliers for each tier
    uint256[] tierMultipliers;
}

/// @dev Encapsulates variables related to Chainlink VRF
/// @dev see: https://docs.chain.link/vrf/v2/subscription#set-up-your-contract-and-request
struct VRFConfig {
    /// @dev Chainlink identifier for prioritizing transactions
    /// different keyhashes have different gas prices thus different priorities
    bytes32 keyHash;
    /// @dev id of Chainlink subscription to VRF for PerpetualMint contract
    uint64 subscriptionId;
    /// @dev maximum amount of gas a user is willing to pay for completing the callback VRF function
    uint32 callbackGasLimit;
    /// @dev number of block confirmations the VRF service will wait to respond
    uint16 minConfirmations;
}

