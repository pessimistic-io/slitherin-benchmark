// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IConsole.sol";
import "./IRNG.sol";
import "./VRFConsumerBaseV2Upgradeable.sol";
import "./CoreUpgradeable.sol";

interface ICaller {
    function fulfill(
        bytes32 requestId,
        uint256[] memory _randomNumbers
    ) external;
}

contract RNGUpgradeable is
    ReentrancyGuardUpgradeable,
    VRFConsumerBaseV2Upgradeable,
    CoreUpgradeable,
    IRNG
{
    /*==================================================== Errors ==========================================================*/

    error UnauthorizedCaller(address _caller);
    error UnknownRequestId(bytes32 _requestId);

    /*==================================================== Events ==========================================================*/

    event RequestedUint256(bytes32 indexed _requestId);
    event ReceivedUint256(bytes32 indexed _requestId, uint256 _response);
    event RequestedUint256Array(bytes32 indexed _requestId, uint256 _size);
    event ReceivedUint256Array(bytes32 indexed _requestId, uint256[] _response);

    /*==================================================== Static Variables ==========================================================*/

    uint32 internal callbackGasLimit;
    uint16 internal requestConfirmations;
    uint64 internal subscriptionId;
    bytes32 internal keyHash;
    VRFCoordinatorV2Interface internal vrfCoordinator;

    mapping(bytes32 => bool) public expectingRequestWithIdToBeFulfilled;
    mapping(bytes32 => address) public callers;
    mapping(address => bool) public callerWhitelist;

    /*==================================================== Modifiers ==========================================================*/

    modifier onlyCaller() {
        if (!callerWhitelist[msg.sender]) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    /*==================================================== Functions ==========================================================*/

    /** @dev Creates a contract. Useful link https://docs.chain.link/vrf/v2/introduction
     * @param _vrfSubscriptionId Id of chainlink subscription that would be used to pay for calls to chainlink VRF.
     * @param _vrfCoordinatorAddress Address of ChainLink VRF contract
     * @param _keyHash key hash for ChainLink VRF Contract
     * @param _callbackGasLimit callback gas limit for ChainLink VRF Contract
     * @param _requestConfirmations confirmations from ChainLink VRF Contract
     */
    function initialize(
        uint64 _vrfSubscriptionId,
        address _vrfCoordinatorAddress,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) public payable initializer {
        __Core_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        subscriptionId = _vrfSubscriptionId;
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinatorAddress);
        keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        VRFConsumerBaseV2Upgradeable.initialize_(_vrfCoordinatorAddress);
    }

    /** @notice Requests a single `uint256`
     */
    function makeRequestUint256() external onlyCaller returns (bytes32) {
        uint256 requestId = vrfCoordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            uint32(1)
        );
        bytes32 newRequestId = bytes32(requestId);
        expectingRequestWithIdToBeFulfilled[newRequestId] = true;
        callers[newRequestId] = msg.sender;
        emit RequestedUint256(newRequestId);
        return newRequestId;
    }

    /** @notice Requests a `uint256[]`
     * @param _size Size of the requested array
     */
    function makeRequestUint256Array(
        uint256 _size
    ) external onlyCaller returns (bytes32) {
        uint256 requestId_ = vrfCoordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            uint32(_size)
        );
        bytes32 newRequestId_ = bytes32(requestId_);
        expectingRequestWithIdToBeFulfilled[newRequestId_] = true;
        callers[newRequestId_] = msg.sender;
        emit RequestedUint256Array(newRequestId_, _size);
        return newRequestId_;
    }

    /** @notice updates Chainlink parameters
     * @param _vrfSubscriptionId *
     * @param _callbackGasLimit *
     * @param _requestConfirmations *
     * @param _keyHash *
     */
    function setRequestParameters(
        uint64 _vrfSubscriptionId,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        bytes32 _keyHash
    ) external nonReentrant onlyGovernance {
        subscriptionId = _vrfSubscriptionId;
        callbackGasLimit = _callbackGasLimit;
        keyHash = _keyHash;
        requestConfirmations = _requestConfirmations;
    }

    /** @notice sets caller whitelist
     * @param _caller *
     * @param _isWhitelisted *
     */
    function setCallerWhitelist(
        address _caller,
        bool _isWhitelisted
    ) external nonReentrant onlyGovernance {
        callerWhitelist[_caller] = _isWhitelisted;
    }

    /*==================================================== Internal Functions ===========================================================*/

    /** @notice Called by the Chainlink through the ChainlinkVRF contract to fulfill the request
     * @param _requestId Request ID
     * @param _randomWords Response
     */
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        bytes32 newRequestId_ = bytes32(_requestId);
        if (!expectingRequestWithIdToBeFulfilled[newRequestId_]) {
            revert UnknownRequestId(newRequestId_);
        }
        expectingRequestWithIdToBeFulfilled[newRequestId_] = false;
        ICaller(callers[newRequestId_]).fulfill(newRequestId_, _randomWords);
        emit ReceivedUint256Array(newRequestId_, _randomWords);
    }

    /*==================================================== View Functions ===========================================================*/

    /** @dev returns whether request id is unfulfuilled
     * @param _requestId *
     */
    function getExpectingRequestWithIdToBeFulfilled(
        bytes32 _requestId
    ) external view override returns (bool) {
        return expectingRequestWithIdToBeFulfilled[_requestId];
    }

    /** @dev returns caller of the created request
     * @param _requestId *
     */
    function getCallers(
        bytes32 _requestId
    ) external view override returns (address) {
        return callers[_requestId];
    }

    /** @dev returns wether game is whitelisted to make a call
     * @param _game *
     */
    function getCallerWhitelist(
        address _game
    ) external view override returns (bool) {
        return callerWhitelist[_game];
    }
}

