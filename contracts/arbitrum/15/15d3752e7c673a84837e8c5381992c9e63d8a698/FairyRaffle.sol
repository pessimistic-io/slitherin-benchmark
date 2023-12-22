// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {TypeAndVersion} from "./TypeAndVersion.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {IRaffleChef} from "./IRaffleChef.sol";
import {IRandomiserCallback} from "./IRandomiserCallback.sol";
import {IRandomProvider} from "./IRandomProvider.sol";

/// @title FairyRaffle (VRF)
/// @author kevincharm
/// @notice The "classic" Fairymint raffler:
///     * Off-chain collection
///         Collect your participants off-chain. All this contract needs is a
///         final merkle root of all the participants. This provides
///         _transparency_: participants can verify that they are included in
///         the participants list and that the merkle root correctly
///         represents a publicly-provided participants list.
///     * On-chain raffle
///         The drawing of random numbers & picking of winners is performed
///         entirely on-chain. This provides _immutability_ and
///         _trustlessness_: the resulting list of winners must be drawn
///         according to the random number and algorithm and therefore is
///         impossible to manipulate, given the random number source is also
///         secure. The algorithm, while efficient enough for on-chain
///         execution, is based on secure cryptographic building blocks: Merkle
///         trees and Feistel ciphers.
///     * Off-chain distribution
///         The winners of the raffle can be computed from the results of the
///         on-chain raffle. As with off-chain collection, this provides
///         _transparency_: participants can verify that the list of winners
///         is indeed correct given the results of the on-chain raffle.
///     Customised for FVM: sourcing randomness from built-in drand
contract FairyRaffle is
    IRandomiserCallback,
    TypeAndVersion,
    OwnableUpgradeable
{
    /// @notice RaffleChef
    address public raffleChef;
    /// @notice Randomiser
    address public randomiser;
    /// @notice FairyRaffleFactory
    address public factory;

    /// @notice Merkle root (commitment) of raffle participants
    bytes32 public participantsMerkleRoot;
    /// @notice Number of raffle participants
    uint256 public nParticipants;
    /// @notice Number of winners that should be drawn during raffle
    uint256 public nWinners;
    /// @notice For record of provenance; could be e.g. an IPFS content hash
    ///     of participants list. This is not used on-chain.
    string public provenance;
    /// @notice Minimum blocks to wait until a VRF request can be fulfilled
    uint16 public minBlocksToWait;

    /// @notice The requestId returned by the randomiser
    uint256 public requestId;
    /// @notice The raffleId returned by RaffleChef
    uint256 public raffleId;
    /// @notice Callback gas limit for receiving random numbers
    uint32 public constant CALLBACK_GAS_LIMIT = 500_000;

    /// @notice Minimum period that must be awaited before a reroll is possible
    /// @dev NB: 24h is the period for which a VRF request can stay pending
    uint256 public constant MINIMUM_REROLL_PERIOD = 24 hours;
    /// @notice Last time a random number was requested
    uint256 public lastRolledAt;

    error Uninitialised();
    error RerollNotYetPossible(uint256 secondsLeft);
    error AlreadyFinalised(uint256 raffleId);
    error CallerNotRandomProvider(
        address caller,
        address expectedRandomProvider
    );
    error NotRolledYet();
    error RequestIdMismatch(
        uint256 receivedRequestId,
        uint256 expectedRequestId
    );

    constructor() {
        _disableInitializers();
    }

    function typeAndVersion() external pure override returns (string memory) {
        return "FairyRaffle 1.1.0";
    }

    /// @notice Commit to a participants list and start the raffle by
    ///     requesting a random number from drand.
    /// @dev Assumes this is called by the factory.
    /// @param minBlocksToWait_ How many (minimum) block confirmations before
    ///     the VRF
    function init(
        address raffleChef_,
        address randomiser_,
        bytes32 participantsMerkleRoot_,
        uint256 nParticipants_,
        uint256 nWinners_,
        string calldata provenance_,
        uint16 minBlocksToWait_
    ) public payable initializer {
        __Ownable_init();

        raffleChef = raffleChef_;
        randomiser = randomiser_;

        participantsMerkleRoot = participantsMerkleRoot_;
        nParticipants = nParticipants_;
        nWinners = nWinners_;
        provenance = provenance_;
        minBlocksToWait = minBlocksToWait_;

        factory = msg.sender;

        _roll();
    }

    /// @dev Assert that the raffle has not been finalised
    function _assertNotFinalised() internal view {
        if (raffleId != 0) {
            revert AlreadyFinalised(raffleId);
        }
    }

    /// @notice Request a random number and record the timestamp.
    /// @dev Does NOT do any checks about whether a roll is allowed
    function _roll() internal {
        lastRolledAt = block.timestamp;
        requestId = IRandomProvider(factory).getRandomNumber{value: msg.value}(
            500_000,
            minBlocksToWait
        );
    }

    /// @notice Re-request a random number. This can be called if a VRF request
    ///     was never fulfilled by the node operator, and the minimum waiting
    ///     period has passed.
    function reroll() public payable onlyOwner {
        _assertNotFinalised();
        if (requestId == 0) {
            revert Uninitialised();
        }
        if (block.timestamp - lastRolledAt <= MINIMUM_REROLL_PERIOD) {
            revert RerollNotYetPossible(lastRolledAt + MINIMUM_REROLL_PERIOD);
        }
        _roll();
    }

    /// @notice See {IRandomiserCallback-receiveRandomWords}
    /// @notice When this function is called by the randomiser, the raffle is
    ///     finalised with a random seed on the RaffleChef, and the winners
    ///     may instantly be queried on the RaffleChef.
    function receiveRandomWords(
        uint256 requestId_,
        uint256[] calldata randomWords
    ) external {
        if (msg.sender != randomiser) {
            revert CallerNotRandomProvider(msg.sender, randomiser);
        }
        uint256 rid = requestId;
        if (rid == 0) {
            revert NotRolledYet();
        }
        if (requestId_ != rid) {
            revert RequestIdMismatch(requestId_, rid);
        }
        _assertNotFinalised();

        raffleId = IRaffleChef(raffleChef).commit(
            participantsMerkleRoot,
            nParticipants,
            nWinners,
            provenance,
            randomWords[0]
        );
    }
}

