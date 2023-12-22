// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IERC721.sol";

interface IRabbleRabble {
    // Raffle
    struct Raffle {
        bool isPublic;
        IERC721 collection;
        uint256 endingTime;
        uint256[] tokenIds;
        uint256 numberOfParticipants;
        address[] participantsList;
        uint256 fees;
        address winner;
        bool requested;
    }

    // Chainlink VRF request
    struct RequestStatus {
        uint256 raffleId;
        uint256 randomWord;
        bool fulfilled;
    }

    // Events

    event RaffleRequest(uint256 indexed raffleId, uint256 indexed requestId);
    event RequestFulfilled(uint256 indexed requestId, uint256 indexed randomWords);
    event RaffleResult(uint256 indexed raffleId, address winner);
    event RaffleCreated(
        uint256 indexed raffleId,
        address indexed creator,
        address indexed collection,
        uint256 timeLimit,
        uint256 numberOfParticipants,
        bool isPublic
    );
    event RaffleJoined(uint256 indexed raffleId, address indexed participant, uint256 indexed tokenId);
    event RaffleRefunded(uint256 indexed raffleId);
    event AddedToWhitelist(uint256 indexed raffleId, address[] accounts);

    // Errors

    error InvalidNumberOfParticipants();
    error EndingTimeReached();
    error UnableToWhitelist();
    error AlreadyFinalized();
    error InvalidTimelimit();
    error WrongMessageValue();
    error UnableToCollect();
    error RaffleNotActive();
    error RaffleIsPublic();
    error RaffleFull();
    error UnableToJoin();
    error AlreadyInRaffle();
    error NotOwnerOf();
    error RequestNotFound();
    error UnableToRefund();
    error Paused();
}

