// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Ownable.sol";

interface VRFCoordinatorV2Interface {
    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId);
}

/**
 * @title VRFAgentConsumer
 * @author PowerPool
 */
contract VRFAgentConsumer is Ownable {
    uint32 public constant VRF_NUM_RANDOM_WORDS = 10;

    address public agent;
    VRFCoordinatorV2Interface public vrfCoordinator;
    bytes32 public vrfKeyHash;
    uint64 public vrfSubscriptionId;
    uint16 public vrfRequestConfirmations;
    uint32 public vrfCallbackGasLimit;

    uint256 public vrfRequestPeriod;
    uint256 public lastVrfRequestAt;

    uint256 public pendingRequestId;
    uint256[] public lastVrfNumbers;

    event SetVrfConfig(VRFCoordinatorV2Interface vrfCoordinator, bytes32 vrfKeyHash, uint64 vrfSubscriptionId, uint16 vrfRequestConfirmations, uint32 vrfCallbackGasLimit, uint256 vrfRequestPeriod);
    event ClearPendingRequestId();

    constructor(address agent_) {
        agent = agent_;
    }

    /*** AGENT OWNER METHODS ***/
    function setVrfConfig(
        VRFCoordinatorV2Interface vrfCoordinator_,
        bytes32 vrfKeyHash_,
        uint64 vrfSubscriptionId_,
        uint16 vrfRequestConfirmations_,
        uint32 vrfCallbackGasLimit_,
        uint256 vrfRequestPeriod_
    ) external onlyOwner {
        vrfCoordinator = vrfCoordinator_;
        vrfKeyHash = vrfKeyHash_;
        vrfSubscriptionId = vrfSubscriptionId_;
        vrfRequestConfirmations = vrfRequestConfirmations_;
        vrfCallbackGasLimit = vrfCallbackGasLimit_;
        vrfRequestPeriod = vrfRequestPeriod_;
        emit SetVrfConfig(vrfCoordinator_, vrfKeyHash_, vrfSubscriptionId_, vrfRequestConfirmations_, vrfCallbackGasLimit_, vrfRequestPeriod_);
    }

    function clearPendingRequestId() external onlyOwner {
        pendingRequestId = 0;
        emit ClearPendingRequestId();
    }

    function rawFulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) external {
        require(msg.sender == address(vrfCoordinator), "sender not vrfCoordinator");
        require(_requestId == pendingRequestId, "request not found");
        lastVrfNumbers = _randomWords;
        pendingRequestId = 0;
        if (vrfRequestPeriod != 0) {
            lastVrfRequestAt = block.timestamp;
        }
    }

    function isReadyForRequest() public view returns (bool) {
        return pendingRequestId == 0 && (vrfRequestPeriod == 0 || lastVrfRequestAt + vrfRequestPeriod < block.timestamp);
    }

    function getLastBlockHash() public virtual view returns (uint256) {
        return uint256(blockhash(block.number - 1));
    }

    function getPseudoRandom() external returns (uint256) {
        if (msg.sender == agent && isReadyForRequest()) {
            pendingRequestId = vrfCoordinator.requestRandomWords(
                vrfKeyHash,
                vrfSubscriptionId,
                vrfRequestConfirmations,
                vrfCallbackGasLimit,
                VRF_NUM_RANDOM_WORDS
            );
        }
        uint256 blockHashNumber = getLastBlockHash();
        if (lastVrfNumbers.length > 0) {
            blockHashNumber += lastVrfNumbers[agent.balance % uint256(VRF_NUM_RANDOM_WORDS)];
        }
        return blockHashNumber;
    }

    function getLastVrfNumbers() external view returns (uint256[] memory) {
        return lastVrfNumbers;
    }
}

