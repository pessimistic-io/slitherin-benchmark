// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2Upgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

interface ICaller {
    function fulfill(
        bytes32 requestId,
        uint256[] memory _randomNumbers
    ) external;
}

contract RNGUpgradeable is Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    VRFConsumerBaseV2Upgradeable
{
    error UnauthorizedCaller(address _caller);
    error UnknownRequestId(bytes32 _requestId);

    address public rootCaller;

    uint32 internal callbackGasLimit;
    uint16 internal requestConfirmations;
    uint64 internal subscriptionId;
    bytes32 internal keyHash;
    VRFCoordinatorV2Interface internal vrfCoordinator;

    mapping(bytes32 => bool) public expectingRequestWithIdToBeFulfilled;
    mapping(bytes32 => address) public callers;
    mapping(address => bool) public callerWhitelist;

    event RequestedUint256(bytes32 indexed requestId);
    event ReceivedUint256(bytes32 indexed requestId, uint256 response);
    event RequestedUint256Array(bytes32 indexed requestId, uint256 size);
    event ReceivedUint256Array(bytes32 indexed requestId, uint256[] response);

    modifier onlyCaller() {
        if (!callerWhitelist[msg.sender]) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    modifier onlyOwnerOrRootCaller() {
        require(
            owner() == _msgSender() ||
                (_msgSender() == rootCaller && rootCaller != address(0)),
            "Ownable: caller is not the owner or root caller"
        );
        _;
    }

    /** @dev Creates a contract. Useful link https://docs.chain.link/vrf/v2/introduction
     * @param _vrfSubscriptionId Id of chainlink subscription that would be used to pay for calls to chainlink VRF.
     * @param _vrfCoordinatorAddress Address of ChainLink VRF contract
     * @param _rootCaller Root caller of that contract.
     * @param _keyHash key hash for ChainLink VRF Contract
     * @param _callbackGasLimit callback gas limit for ChainLink VRF Contract
     * @param _requestConfirmations confirmations from ChainLink VRF Contract
     */
    function initialize(
        uint64 _vrfSubscriptionId,
        address _vrfCoordinatorAddress,
        address _rootCaller,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) public payable initializer {
        subscriptionId = _vrfSubscriptionId;
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinatorAddress);
        keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        rootCaller = _rootCaller;
        VRFConsumerBaseV2Upgradeable.initialize_(_vrfCoordinatorAddress);
        __Ownable_init();
        __ReentrancyGuard_init();
    }
    
    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

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

    /// @notice Requests a `uint256[]`
    /// @param size Size of the requested array
    function makeRequestUint256Array(
        uint256 size
    ) external onlyCaller returns (bytes32) {
        uint256 requestId = vrfCoordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            uint32(size)
        );
        bytes32 newRequestId = bytes32(requestId);
        expectingRequestWithIdToBeFulfilled[newRequestId] = true;
        callers[newRequestId] = msg.sender;
        emit RequestedUint256Array(newRequestId, size);
        return newRequestId;
    }

    /// @notice Called by the Chainlink through the ChainlinkVRF contract to
    /// fulfill the request
    /// @param requestId Request ID
    /// @param randomWords Response
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        bytes32 newRequestId = bytes32(requestId);
        if (!expectingRequestWithIdToBeFulfilled[newRequestId]) {
            revert UnknownRequestId(newRequestId);
        }
        expectingRequestWithIdToBeFulfilled[newRequestId] = false;
        ICaller(callers[newRequestId]).fulfill(newRequestId, randomWords);
        emit ReceivedUint256Array(newRequestId, randomWords);
    }

    function setRequestParameters(
        uint64 _vrfSubscriptionId,
        uint32 _callbackGasLimit,
        bytes32 _keyHash,
        uint16 _requestConfirmations
    ) external nonReentrant onlyOwner {
        subscriptionId = _vrfSubscriptionId;
        callbackGasLimit = _callbackGasLimit;
        keyHash = _keyHash;
        requestConfirmations = _requestConfirmations;
    }

    function setNewRootCaller(address _newRootCaller) public onlyOwner {
        rootCaller = _newRootCaller;
    }

    function setCallerWhitelist(
        address _caller,
        bool _isWhitelisted
    ) external nonReentrant onlyOwnerOrRootCaller {
        callerWhitelist[_caller] = _isWhitelisted;
    }
}

