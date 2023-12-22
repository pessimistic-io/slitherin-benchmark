// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity 0.8.17;

import "./AccessControlEnumerable.sol";
import "./IBridgeV2.sol";
import "./IGateKeeper.sol";
import "./RequestIdLib.sol";
import "./IValidatedDataReciever.sol";


/**
 * @notice This is for test purpose.
 *
 * @dev Short life cycle
 * @dev POOL_1#sendRequestTest --> {logic bridge} --> POOL_2#setPendingRequestsDone
 */
contract MockDexPool is IValidatedDataReciever, AccessControlEnumerable {
    uint256 public testData = 0;
    address public bridge;
    address public gateKeeper;
    mapping(bytes32 => uint256) public requests;
    bytes32[] public doubleRequestIds;
    uint256 public totalRequests = 0;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    event RequestSent(bytes32 reqId);
    event RequestReceived(uint256 data);
    event RequestReceivedV2(bytes32 reqId, uint256 data);
    event TestEvent(bytes testData_, address receiveSide, address oppositeBridge, uint256 chainId);

    constructor(address bridge_, address gatekeeper_) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        bridge = bridge_;
        gateKeeper = gatekeeper_;
    }

    function receiveValidatedData(bytes4 selector, address from, uint64 chainIdFrom) external virtual returns (bool) {
        // require(from == router, "Router: wrong sender");
        // require(selector == RouterV2.resume.selector, "Router: wrong selector");
        return true;
    }

    function sendTest2(
        bytes memory testData_,
        address receiveSide_,
        address oppositeBridge_,
        uint256 chainId_
    ) external onlyRole(OPERATOR_ROLE) {
        emit TestEvent(testData_, receiveSide_, oppositeBridge_, chainId_);
    }

    /**
     * @notice send request like second part of pool
     *
     * @dev LIFE CYCLE
     * @dev ${this pool} -> POOL_2
     * @dev ${this func} ->  bridge#transmitRequest -> node -> adpater#receiveRequest -> mockDexPool_2#receiveRequestTest -> bridge#transmitResponse(reqId) -> node -> adpater#receiveResponse -> mockDexPool_1#setPendingRequestsDone
     *
     */
    function sendRequestTestV2(
        uint256 testData_,
        address receiveSide,
        address oppositeBridge,
        uint256 chainId
    ) external onlyRole(OPERATOR_ROLE) {
        require(receiveSide != address(0), "MockDexPool: zero address");

        uint256 nonce = IBridgeV2(bridge).nonces(msg.sender);
        bytes32 requestId = RequestIdLib.prepareRqId(
            bytes32(uint256(uint160(oppositeBridge))),
            chainId,
            block.chainid,
            bytes32(uint256(uint160(receiveSide))),
            bytes32(uint256(uint160(msg.sender))),
            nonce
        );
        bytes memory output = abi.encodeWithSelector(
            bytes4(keccak256(bytes("receiveRequestTest(uint256,bytes32)"))),
            testData_,
            requestId
        );

        bytes memory info = abi.encodeWithSelector(
            IValidatedDataReciever.receiveValidatedData.selector,
            bytes4(keccak256(bytes("receiveRequestTest(uint256,bytes32)"))),
            msg.sender,
            block.chainid
        );

        bytes memory out = abi.encode(output, info);

        IBridgeV2.SendParams memory sendParams = IBridgeV2.SendParams(
            requestId,
            out,
            receiveSide,
            chainId
        );

        IBridgeV2(bridge).sendV2(sendParams, msg.sender, nonce);

        emit RequestSent(requestId);
    }

    function sendViaGatekeeper(
        uint256 testData_,
        uint256 chainId,
        address receiveSide,
        address oppositeBridge,
        address payToken
    ) external onlyRole(OPERATOR_ROLE) {
        require(receiveSide != address(0), "MockDexPool: zero address");

        uint256 nonce = IBridgeV2(bridge).nonces(msg.sender);
        bytes32 requestId = RequestIdLib.prepareRqId(
            bytes32(uint256(uint160(oppositeBridge))),
            chainId,
            block.chainid,
            bytes32(uint256(uint160(receiveSide))),
            bytes32(uint256(uint160(msg.sender))),
            nonce
        );
        bytes memory output = abi.encodeWithSelector(
            bytes4(keccak256(bytes("receiveRequestTest(uint256,bytes32)"))),
            testData_,
            requestId
        );

        IGateKeeper(gateKeeper).sendData(
            output,
            receiveSide,
            chainId,
            payToken
        );
    }

    function sendRequestTestV2Unsafe(
        uint256 testData_,
        address receiveSide,
        address oppositeBridge,
        uint256 chainId,
        bytes32 requestId,
        uint256 nonce
    ) external onlyRole(OPERATOR_ROLE) {
        require(receiveSide != address(0), "MockDexPool: zero address");

        bytes memory output = abi.encodeWithSelector(
            bytes4(keccak256(bytes("receiveRequestTest(uint256,bytes32)"))),
            testData_,
            requestId
        );

        IBridgeV2.SendParams memory sendParams = IBridgeV2.SendParams(
            requestId,
            output,
            receiveSide,
            chainId
        );

        IBridgeV2(bridge).sendV2(sendParams, msg.sender, nonce);

        emit RequestSent(requestId);
    }

    /**
     * @notice receive request on the second part of pool
     *
     * @dev LIFE CYCLE
     * @dev POOL_1 -> ${this pool}
     * @dev mockDexPool_1#sendRequestTest -> bridge#transmitRequest -> node -> adpater#receiveRequest -> ${this func} -> bridge#transmitResponse(reqId) -> node -> adpater#receiveResponse -> mockDexPool_1#setPendingRequestsDone
     */
    function receiveRequestTest(uint256 newData, bytes32 reqId) public {
        require(msg.sender == bridge, "MockDexPool: only certain bridge");

        if (requests[reqId] != 0) {
            doubleRequestIds.push(reqId);
        }
        requests[reqId]++;
        totalRequests++;

        testData = newData;
        emit RequestReceived(newData);
        emit RequestReceivedV2(reqId, newData);
    }

    function sigHash(string memory data) public pure returns (bytes8) {
        return bytes8(sha256(bytes(data)));
    }

    function doubles() public view returns (bytes32[] memory) {
        return doubleRequestIds;
    }

    function doubleRequestError() public view returns (uint256) {
        return doubleRequestIds.length;
    }

    function clearStats() public {
        delete doubleRequestIds;
        totalRequests = 0;
    }

    function calcRequestId(
        address secondPartPool,
        address oppBridge,
        uint256 chainId
    ) external view returns (bytes32, uint256) {
        uint256 nonce = IBridgeV2(bridge).nonces(msg.sender);
        bytes32 reqId = RequestIdLib.prepareRqId(
            bytes32(uint256(uint160(oppBridge))),
            chainId,
            block.chainid,
            bytes32(uint256(uint160(secondPartPool))),
            bytes32(uint256(uint160(msg.sender))),
            nonce
        );
        return (reqId, nonce);
    }
}

