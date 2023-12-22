// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";
import "./CCIPReceiver.sol";
import "./Client.sol";
import "./IRouterClient.sol";

contract OmniChainVRFSourceWithCCIP is VRFConsumerBaseV2, CCIPReceiver {
    event MessageSent(bytes32 messageId);
    event RequestSent(uint256 indexed _requestId, uint32 _numWords);
    event RequestFulfilled(uint256 indexed _requestId, uint256[] _randomWords);
    event DepositETH(address indexed _sender, uint256 _amount);
    event WithdrawETH(
        address indexed _sender,
        address indexed _reciever,
        uint256 _amount
    );

    error RequestNotFound(uint256 requestId);

    struct RequestStatus {
        bool exists;
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256[] randomWords;
    }
    mapping(uint256 => RequestStatus)
        public requests; /* requestId --> requestStatus */

    uint64 public immutable subscriptionId;
    bytes32 public immutable keyHash;
    VRFCoordinatorV2Interface public immutable coordinator;

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    uint32 constant callbackGasLimit = 1000000;
    uint16 constant requestConfirmations = 3;
    uint32 constant numWords = 1;

    address payable public refundAddress;

    address public immutable router;

    struct DestinationRequestInfo {
        uint64 chainSelector;
        uint256 requestId;
        bytes sender;
    }

    mapping(uint256 => DestinationRequestInfo) public dstRequests;

    constructor(
        uint64 _subscriptionId,
        address _vrfCoordinator,
        bytes32 _keyHash,
        address payable _refundAddress,
        address _router
    ) VRFConsumerBaseV2(_vrfCoordinator) CCIPReceiver(_router) {
        coordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        refundAddress = _refundAddress;
        router = _router;
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        uint256 requestId = abi.decode(message.data, (uint256));

        _requestRandomNumber(
            message.sourceChainSelector,
            message.sender,
            requestId
        );
    }

    function _requestRandomNumber(
        uint64 _dstChainSelector,
        bytes memory sender,
        uint256 _dstRequestId
    ) internal returns (uint256 requestId) {
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

        dstRequests[requestId] = DestinationRequestInfo({
            chainSelector: _dstChainSelector,
            requestId: _dstRequestId,
            sender: sender
        });

        emit RequestSent(requestId, numWords);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        RequestStatus storage request = requests[_requestId];
        if (!request.exists) revert RequestNotFound(_requestId);

        request.fulfilled = true;
        request.randomWords = _randomWords;

        DestinationRequestInfo memory dstRequestInfo = dstRequests[_requestId];

        bytes memory data = abi.encode(dstRequestInfo.requestId, _randomWords[0]);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: dstRequestInfo.sender,
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0)
        });

        uint256 fee = IRouterClient(router).getFee(
            dstRequestInfo.chainSelector,
            message
        );

        bytes32 messageId = IRouterClient(router).ccipSend{value: fee}(
            dstRequestInfo.chainSelector,
            message
        );

        emit MessageSent(messageId);
        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getNumberOfRequests() external view returns (uint256) {
        return requestIds.length;
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256[] memory randomWords) {
        RequestStatus memory request = requests[_requestId];
        if (!request.exists) revert RequestNotFound(_requestId);
        return (request.fulfilled, request.randomWords);
    }

    function depositETH() external payable {
        emit DepositETH(msg.sender, msg.value);
    }

    function withdrawETH(uint256 amount) external {
        refundAddress.transfer(amount);

        emit WithdrawETH(msg.sender, refundAddress, amount);
    }

    receive() external payable {}
}

