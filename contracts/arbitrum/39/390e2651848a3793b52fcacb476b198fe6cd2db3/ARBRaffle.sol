// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";
import "./AccessControl.sol";

contract ARBRaffle is VRFConsumerBaseV2, AccessControl {
    uint256 public randomResult;
    bool public firstRaffleDone;

    struct Trader {
        address account;
        uint256 volume;
    }

    Trader[] public traders;
    uint256[] public volumeScores;
    address[3] public winners1stRaffle;
    address public winner2ndRaffle;
    mapping(address => bool) public traderAdded;
    bool tradersExist;

    event Winners1stRaffleCalculated(address[3] winners1stRaffle);
    event Winner2ndRaffleCalculated(address winner2ndRaffle);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    // Roles for access control
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
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
    uint256 public lastRequestId;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 vrfKeyHash;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
    // so 100,000 is a safe default for this example contract. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 vrfCallbackGasLimit = 100000;

    uint16 vrfRequestConfirmations = 3;

    uint32 vrfNumWords = 1;

    constructor(
        uint64 subscriptionId,
        address vrfCoordinatorAddr,
        bytes32 _vrfKeyHash
    )
        VRFConsumerBaseV2(vrfCoordinatorAddr)
        AccessControl()
    {
        s_subscriptionId = subscriptionId;

        // Set up access control
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);

        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinatorAddr);
        vrfKeyHash = _vrfKeyHash;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    function addTraders(address[] memory _accounts, uint256[] memory _volumes)
        external
        onlyAdmin
    {
        require(
            _accounts.length == _volumes.length,
            "Accounts and volumes arrays must have the same length"
        );
        for (uint256 i = 0; i < _accounts.length; i++) {
            require(_accounts[i] != address(0), "Address 0x0 not allowed");  
            require(_volumes[i] > 0, "Volume must be > 0");  
            if(!traderAdded[_accounts[i]]) { 
                traderAdded[_accounts[i]] = true;
                traders.push(Trader(_accounts[i], _volumes[i]));
            }
        }
        tradersExist = true;
    }

    function removeAllTraders() external onlyAdmin 
    {
        delete traders;
        delete volumeScores;
        tradersExist = false;
        for (uint256 i = 0; i < winners1stRaffle.length; i++) {
            winners1stRaffle[i] = address(0);
        }
        winner2ndRaffle = address(0);
        firstRaffleDone = false;
    }


    function calculateVolumeScore(uint256 volume)
        private
        pure
        returns (uint256)
    {
        if (volume < 10000) {
            return volume;
        } else {
            return 10000 + (volume - 10000) / 2;
        }
    }

    function generateVolumeScores() external onlyAdmin {
        require(tradersExist, "Add traders first");
        for (uint256 i = 0; i < traders.length; i++) {
            volumeScores.push(calculateVolumeScore(traders[i].volume));
        }
    }

    function calculate1stRaffleWinners() external onlyAdmin {
        require(
            randomResult != 0,
            "Random number not generated yet"
        );
        uint256 totalVolumeScore;
        for (uint256 i = 0; i < volumeScores.length; i++) {
            totalVolumeScore += volumeScores[i];
        }

        for (uint256 j = 0; j < 3; j++) {
            uint256 randomSelection = randomResult % totalVolumeScore;
            uint256 selectedTrader;
            for (uint256 i = 0; i < volumeScores.length; i++) {
                if (randomSelection < volumeScores[i]) {
                    selectedTrader = i;
                    break;
                }
                randomSelection -= volumeScores[i];
            }

            winners1stRaffle[j] = traders[selectedTrader].account;

            totalVolumeScore -= volumeScores[selectedTrader];
            volumeScores[selectedTrader] = 0;
            randomResult = uint256(keccak256(abi.encodePacked(randomResult)));
        }

        firstRaffleDone = true;
        emit Winners1stRaffleCalculated(winners1stRaffle);
    }

    function calculate2ndRaffleWinners() external onlyAdmin {
        require(firstRaffleDone == true, "1stRaffle not done yet");

        uint256[5] memory topVolumeScores;
        address[5] memory topTraders;

        // Find the top 5 traders with the highest volume scores
        for (uint256 i = 0; i < volumeScores.length; i++) {
            for (uint256 j = 0; j < 5; j++) {
                if (volumeScores[i] > topVolumeScores[j]) {
                    // Shift the scores and traders below the current position
                    for (uint256 k = 4; k > j; k--) {
                        topVolumeScores[k] = topVolumeScores[k - 1];
                        topTraders[k] = topTraders[k - 1];
                    }
                    // Update the current position with the new trader and score
                    topVolumeScores[j] = volumeScores[i];
                    topTraders[j] = traders[i].account;
                    break;
                }
            }
        }

        // Randomly select a winner among the top 5 traders
        uint256 randomIndex = randomResult % 5;
        winner2ndRaffle = topTraders[randomIndex];

        emit Winner2ndRaffleCalculated(winner2ndRaffle);
    }


    function viewWinners() public view returns (address[3] memory, address) {
        return (winners1stRaffle, winner2ndRaffle);
    }

    function getRandomNumber() external onlyAdmin returns (uint256 requestId) {
        // Will revert if subscription is not set and funded.
        requestId = COORDINATOR.requestRandomWords(
            vrfKeyHash,
            s_subscriptionId,
            vrfRequestConfirmations,
            vrfCallbackGasLimit,
            vrfNumWords
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, vrfNumWords);
        return requestId;
    }

    function getRequestStatus(uint256 _requestId)
        external
        view
        returns (bool fulfilled, uint256[] memory randomWords)
    {
        require(
            _requestId == lastRequestId,
            "Invalid request ID"
        );
        return (randomResult != 0, new uint256[](0));
    }
    
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        randomResult = _randomWords[0];
        emit RequestFulfilled(_requestId, _randomWords);
    }
}

