// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";
import "./IACLManager.sol";
import "./IBids.sol";

contract ChainlinkVRFAdapter is VRFConsumerBaseV2
{
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(
        uint256 requestId,
        uint256[] randomWords
    );
    error RequestNotFound(uint256 requestId);

    struct RequestStatus {
        bool exists;
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256[] randomWords;
    }
    mapping(uint256 => RequestStatus) public requests; /* requestId --> requestStatus */

    uint64 public immutable subscriptionId;
    bytes32 public immutable keyHash;
    VRFCoordinatorV2Interface immutable coordinator;
    IACLManager public immutable aclManager;

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    uint32 constant callbackGasLimit = 1000000;
    uint16 constant requestConfirmations = 3;
    uint32 constant numWords = 1;

    struct RaffleInfo {
        address bidPool;
        uint256 raffleId;
    }

    mapping(uint256 => RaffleInfo) public raffles;

    modifier onlyBids() {
        require(aclManager.isBidsContract(msg.sender), "ONLY_BIDS_CONTRACT");
        _;
    }

    constructor(
        uint64 _subscriptionId,
        address _vrfCoordinator,
        bytes32 _keyHash,
        address _aclManager
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        coordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        aclManager = IACLManager(_aclManager);
    }

    function requestRandomNumber(uint256 raffleId) external onlyBids returns (uint256 requestId) {
        requestId = coordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;

        raffles[requestId] = RaffleInfo({
            bidPool: msg.sender,
            raffleId: raffleId
        });

        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        RequestStatus storage request = requests[_requestId];
        if (!request.exists) revert RequestNotFound(_requestId);
        request.fulfilled = true;
        request.randomWords = _randomWords;

        RaffleInfo memory raffleInfo = raffles[_requestId];
        IBids(raffleInfo.bidPool).drawCallback(raffleInfo.raffleId, _randomWords[0]);

        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getNumberOfRequests() external view returns (uint256) {
        return requestIds.length;
    }

    function getRequestStatus(
        uint256 _requestId
    )
        external
        view
        returns (bool fulfilled, uint256[] memory randomWords)
    {
        RequestStatus memory request = requests[_requestId];
        if (!request.exists) revert RequestNotFound(_requestId);
        return (request.fulfilled, request.randomWords);
    }
}

