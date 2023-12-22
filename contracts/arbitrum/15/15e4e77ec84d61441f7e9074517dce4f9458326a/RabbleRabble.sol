// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

//   ,,==.
//  //    `
// ||      ,--~~~~-._ _(\--,_
//  \\._,-~   \      '    *  `o
//   `---~\( _/,___( /_/`---~~
//         ``==-    `==-,

import "./Ownable.sol";
import "./IERC721Receiver.sol";
import "./ReentrancyGuard.sol";
import "./VRFConsumerBaseV2.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./IRabbleRabble.sol";

contract RabbleRabble is Ownable, VRFConsumerBaseV2, IERC721Receiver, IRabbleRabble, ReentrancyGuard {
    bool public paused;
    address public multisig;
    address public addressZero = address(0);
    uint256 public maxTimeLimit;

    uint256 public raffleCounter;
    mapping(uint256 => Raffle) public raffles;
    mapping(uint256 => mapping(address => bool)) public raffleIdToWhitelisted;

    uint256 public fee;
    uint256 public collectableFees;

    mapping(uint256 => RequestStatus) public requests;

    VRFCoordinatorV2Interface public vrfCoordinator;

    uint64 public subscriptionId;
    uint32 public numWords = 1;
    uint32 public callbackGasLimit;
    uint16 public requestConfirmations = 3;
    bytes32 public keyHash;

    modifier isPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier EOA() {
        if (msg.sender != tx.origin) revert UnableToJoin();
        _;
    }

    /**
     * @notice Constructor
     * @param _multisig The address of the multisig wallet
     * @param _fee The fee in wei for each raffle
     * @param _maxTimeLimit The max time limit for each raffle
     * @param _vrfCoordinator The address of the VRF Coordinator
     * @param _keyHash The key hash for the VRF Coordinator
     * @param _subscriptionId The subscription id for the VRF Coordinator
     * @param _callbackGasLimit The callback gas limit for the VRF Coordinator
     */
    constructor(
        address _multisig,
        uint256 _fee,
        uint256 _maxTimeLimit,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        maxTimeLimit = _maxTimeLimit;
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
        multisig = _multisig;
        fee = _fee;
    }

    ////////////////////
    //      View      //
    ////////////////////

    /**
     * @notice IERC721Receiver implementation
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Retrieves entire raffle struct
     * @param raffleId The id of the raffle
     * @return Raffle struct
     */
    function getRaffle(uint256 raffleId) external view returns (Raffle memory) {
        return raffles[raffleId];
    }

    ////////////////////
    //     Public     //
    ////////////////////

    /**
     * @notice Create public raffle with no whitelist where anyone can participate
     * @param collection IERC721 address of the collection being raffled among participants
     * @param numberOfParticipants The number of participants in the raffle
     * @param tokenId The tokenId of the NFT being raffled owned by raffle creator
     * @param timeLimit The time limit for the raffle to be filled
     */
    function createPublicRaffle(IERC721 collection, uint256 numberOfParticipants, uint256 tokenId, uint256 timeLimit)
        external
        payable
    {
        if (msg.value < fee) revert WrongMessageValue();
        address[] memory emptyWhitelist = new address[](0);

        _createNewRaffle(collection, timeLimit, tokenId, numberOfParticipants, emptyWhitelist);
    }

    /**
     * @notice Create private raffle with whitelist where only whitelisted users can participate and add users to whitelist
     * @param collection IERC721 address of the collection being raffled among participants
     * @param numberOfParticipants The number of participants in the raffle
     * @param tokenId The tokenId of the NFT being raffled owned by raffle creator
     * @param whitelist The list of addresses that are whitelisted to participate in the raffle
     * @param timeLimit The time limit for the raffle to be filled
     */
    function createPrivateRaffle(
        IERC721 collection,
        uint256 numberOfParticipants,
        uint256 tokenId,
        address[] memory whitelist,
        uint256 timeLimit
    ) external payable {
        if (msg.value != fee) revert WrongMessageValue();

        _createNewRaffle(collection, timeLimit, tokenId, numberOfParticipants, whitelist);
    }

    /**
     * @notice Join a raffle by indicating raffleId and tokenId of the collection being raffled
     * If raffle is not full by the time raffle ending time is reached, refunds all users with paid fees and NFTs.
     * If raffle is full, calls Chainlink VRF to select a winner and transfers NFTs to winner.
     * @param raffleId The id of the raffle
     * @param tokenId The tokenId of the NFT being raffled
     */
    function joinRaffle(uint256 raffleId, uint256 tokenId) external payable isPaused EOA {
        Raffle storage raffle = raffles[raffleId];
        // check if raffle is active
        if (raffle.winner != addressZero) revert RaffleNotActive();
        // check if raffle is time limit is over
        if (raffle.endingTime < block.timestamp) {
            _refundRaffle(raffleId);
        } else {
            // check if fee is paid
            if (msg.value != fee) revert WrongMessageValue();

            // check if raffle is full
            if (raffle.participantsList.length >= raffle.numberOfParticipants) {
                revert RaffleFull();
            }

            // check if user is whitelisted
            if (!raffle.isPublic && !raffleIdToWhitelisted[raffleId][msg.sender]) {
                revert UnableToJoin();
            }

            if (raffle.collection.ownerOf(tokenId) != msg.sender) {
                revert NotOwnerOf();
            }

            // check if user is already in the raffle
            for (uint256 i = 0; i < raffle.participantsList.length; i++) {
                if (raffle.participantsList[i] == msg.sender) {
                    revert AlreadyInRaffle();
                }
            }

            // Transfer NFT to rabble contract
            _transferToVault(raffles[raffleId].collection, tokenId);

            // Store fees
            raffle.fees += msg.value;

            // add user to the raffle
            raffles[raffleId].participantsList.push(msg.sender);

            // Register NFT to raffle
            raffles[raffleId].tokenIds.push(tokenId);

            // check if raffle is full, if so, request random number and finalize raffle
            if (raffles[raffleId].participantsList.length >= raffles[raffleId].numberOfParticipants) {
                raffle.requested = true;
                uint256 requestId = vrfCoordinator.requestRandomWords(
                    keyHash, subscriptionId, requestConfirmations, callbackGasLimit, numWords
                );
                requests[requestId] = RequestStatus({raffleId: raffleId, randomWord: 0, fulfilled: false});
                emit RaffleRequest(raffleId, requestId);
            }

            emit RaffleJoined(raffleId, msg.sender, tokenId);
        }
    }

    /**
     * @notice Adds more users to whitelist. Anyone that has been whitelisted can whitelist users
     * @param raffleId The id of the raffle
     * @param whitelist The list of addresses to be whitelisted
     */
    function addToWhitelist(uint256 raffleId, address[] calldata whitelist) external isPaused {
        Raffle storage raffle = raffles[raffleId];
        if (raffle.winner != addressZero) revert RaffleNotActive();
        if (raffle.endingTime < block.timestamp) {
            revert EndingTimeReached();
        }
        if (raffle.isPublic) revert RaffleIsPublic();
        if (!raffleIdToWhitelisted[raffleId][msg.sender]) {
            revert UnableToWhitelist();
        }
        for (uint256 i; i < whitelist.length; i++) {
            raffleIdToWhitelisted[raffleId][whitelist[i]] = true;
        }

        emit AddedToWhitelist(raffleId, whitelist);
    }

    ////////////////////
    //     Owner      //
    ////////////////////

    /**
     * @notice Collects fees from the contract
     */
    function collectFee() external onlyOwner nonReentrant {
        uint256 collect = collectableFees;
        collectableFees = 0;
        (bool sent,) = multisig.call{value: collect}("");
        if (!sent) {
            revert UnableToCollect();
        }
    }

    /**
     * @notice Toggles paused state between true and false
     */
    function togglePause() external onlyOwner {
        paused = !paused;
    }

    /**
     * @notice Sets the fee for creating a raffle
     * @param _fee The new fee
     */
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    /**
     * @notice Sets the max time limit users can set for a raffle
     * @param _maxTimeLimit The new max time limit
     */
    function setMaxTimeLimit(uint256 _maxTimeLimit) external onlyOwner {
        maxTimeLimit = _maxTimeLimit;
    }

    function refundRaffle(uint256 raffleId) external onlyOwner {
        _refundRaffle(raffleId);
    }

    ////////////////////
    //    Internal    //
    ////////////////////

    // full refund if the lobby isnt filled
    function _refundRaffle(uint256 raffleId) internal nonReentrant {
        Raffle storage raffle = raffles[raffleId];

        // Check if request to chainlink has been made already
        if (raffle.requested) revert AlreadyFinalized();

        // Check if raffle is active
        if (raffle.winner != addressZero) revert RaffleNotActive();

        // If user tried joing a raffle that is not full but was late, refund them
        if (msg.value > 0) {
            (bool sent,) = msg.sender.call{value: msg.value}("");
            if (!sent) {
                revert UnableToRefund();
            }
        }

        // Refund all participants
        uint256 feeToReturn = raffle.fees / raffle.participantsList.length;
        raffle.fees = 0;
        for (uint256 i; i < raffle.participantsList.length; i++) {
            raffle.collection.transferFrom(address(this), raffle.participantsList[i], raffle.tokenIds[i]);

            (bool sent,) = raffle.participantsList[i].call{value: feeToReturn}("");
            if (!sent) {
                revert UnableToRefund();
            }
        }
        emit RaffleRefunded(raffleId);
    }

    // Generic create raffle function
    function _createNewRaffle(
        IERC721 collection,
        uint256 timeLimit,
        uint256 tokenId,
        uint256 numberOfParticipants,
        address[] memory whitelist
    ) internal isPaused EOA {
        if (timeLimit > maxTimeLimit) revert InvalidTimelimit();
        if (numberOfParticipants < 2 || numberOfParticipants > 100) revert InvalidNumberOfParticipants();
        if (collection.ownerOf(tokenId) != msg.sender) revert NotOwnerOf();

        // transfer token to raffle contract
        _transferToVault(collection, tokenId);

        // create a dynamic array of addresses that includes msg.sender and tokenIds that includes tokenId
        address[] memory participants = new address[](1);
        participants[0] = msg.sender;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        bool isPublic = whitelist.length == 0;

        // register new raffle
        raffles[++raffleCounter] = Raffle({
            isPublic: isPublic,
            collection: collection,
            endingTime: timeLimit + block.timestamp,
            tokenIds: tokenIds,
            numberOfParticipants: numberOfParticipants,
            participantsList: participants,
            fees: fee,
            winner: addressZero,
            requested: false
        });

        // if its a private raffle, add msg.sender and whitelist list to raffleIdToWhitelisted mapping
        if (!isPublic) {
            raffleIdToWhitelisted[raffleCounter][msg.sender] = true;
            for (uint256 i = 0; i < whitelist.length; i++) {
                raffleIdToWhitelisted[raffleCounter][whitelist[i]] = true;
            }
        }

        emit RaffleCreated(
            raffleCounter, msg.sender, address(collection), timeLimit + block.timestamp, numberOfParticipants, isPublic
        );
    }

    // Transfer to Vault
    function _transferToVault(IERC721 collection, uint256 tokenId) internal {
        _transferNFT(collection, msg.sender, tokenId, address(this));
    }

    // Transfer an NFT from one address to another
    function _transferNFT(IERC721 collection, address from, uint256 tokenId, address to) internal {
        collection.safeTransferFrom(from, to, tokenId);
    }

    // Tansfer To winner
    function _transferToWinner(IERC721 collection, uint256[] memory tokenIds, address winner) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _transferNFT(collection, address(this), tokenIds[i], winner);
        }
    }

    // VRF Callback
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        if (requests[_requestId].raffleId == 0) revert RequestNotFound();
        requests[_requestId].fulfilled = true;
        requests[_requestId].randomWord = _randomWords[0];

        _fulfillRaffle(_randomWords[0], requests[_requestId].raffleId);

        emit RequestFulfilled(_requestId, _randomWords[0]);
    }

    // Fulfill the raffle
    function _fulfillRaffle(uint256 randomNumber, uint256 raffleId) internal {
        Raffle storage raffle = raffles[raffleId];

        // Select random winner
        uint256 winnerIndex = randomNumber % raffle.participantsList.length;

        // set winner
        raffle.winner = raffle.participantsList[winnerIndex];

        // transfer NFTs to winner
        _transferToWinner(raffle.collection, raffle.tokenIds, raffle.participantsList[winnerIndex]);

        // add collectable fees
        collectableFees += raffles[raffleId].fees;

        emit RaffleResult(raffleId, raffle.participantsList[winnerIndex]);
    }
}

