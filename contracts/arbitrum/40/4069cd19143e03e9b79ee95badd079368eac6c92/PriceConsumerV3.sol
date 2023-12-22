// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;
import "./VRFConsumerBaseV2.sol";
import "./AggregatorV3Interface.sol";
import "./Ownable.sol";
import "./VRFCoordinatorV2Interface.sol";

contract PriceConsumerV3 is VRFConsumerBaseV2, Ownable{
    AggregatorV3Interface public priceFeed;


    bytes32 public keyHash;
    uint256 public fee;
    uint256 public randomResult;



    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
    }
    mapping(uint256 => RequestStatus)
        public s_requests; /* requestId --> requestStatus */
    VRFCoordinatorV2Interface COORDINATOR;

    // Your subscription ID.
    uint64 s_subscriptionId;

    // past requests Id.
    uint256[] public requestIds;
    bytes32 oldRequestId;
    uint256 public lastRequestId;
    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
    // so 100,000 is a safe default for this example contract. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 callbackGasLimit = 1;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;


    constructor() VRFConsumerBaseV2(0x41034678D6C633D8a95c75e1138A360a28bA15d1)
    {
        COORDINATOR = VRFCoordinatorV2Interface(
            0x41034678D6C633D8a95c75e1138A360a28bA15d1
        );
        s_subscriptionId = 15;
        // priceFeed = AggregatorV3Interface(0x18E4058491C3F58bC2f747A9E64cA256Ed6B318d);
    }


    // function getLatestPrice() public view returns (int){
    //     (,int latestRoundData,,,) = priceFeed.latestRoundData();
    //     return latestRoundData;
    // }
    // function getDecimals() public view returns (uint8){
    //     uint8 decimals = priceFeed.decimals();
    //     return decimals;
    // }
    // function getRandomNumber() public onlyOwner returns (bytes32){
    //     return requestRandomness(keyHash, fee);
    // }
    // function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override{
    //     randomResult = randomness;
    //     oldRequestId = requestId;
    // }
    function returnAll () external onlyOwner view returns(bytes32, uint256, uint256){
        return (keyHash, fee, randomResult);
    }

    function setCallbackGasLimit (uint32 limit) external onlyOwner{
        callbackGasLimit = limit;
    }

    // Assumes the subscription is funded sufficiently.
    function requestRandomWords()
        external
        onlyOwner
        returns (uint256 requestId)
    {
        // Will revert if subscription is not set and funded.
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256[] memory randomWords) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }
}
