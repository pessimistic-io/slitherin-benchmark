// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "./Ownable.sol";

error RouteIdNotFound();
error FailedToVerify();
error RouteIdNotMatched();
error AmountNotMatched();
error RecipientNotMatched();
error ToChainIdNotMatched();
error TokenNotMatched();
error SignatureNotMatched();

contract SocketVerifier is Ownable {
    address public socketGateway;

    mapping(uint32 => address) public routeIdsToVerifiers;

    struct SocketRequest {
        uint256 amount;
        address recipient;
        uint256 toChainId;
        address token;
        bytes4 signature;
    }

    struct UserRequest {
        uint32 routeId;
        bytes socketRequest;
    }

    struct UserRequestValidation {
        uint32 routeId;
        SocketRequest socketRequest;
    }

    constructor(address _owner, address _socketGateway) Ownable(_owner) {
        socketGateway = _socketGateway;
    }

    function parseCallData(
        bytes calldata callData
    ) public returns (UserRequest memory) {
        // get calldata signature from first 4 bytes
        uint32 routeId = uint32(bytes4(callData[0:4]));
        if (routeIdsToVerifiers[routeId] != address(0)) {
            (bool success, bytes memory socketRequest) = routeIdsToVerifiers[
                routeId
            ].call(callData[4:]);
            if (!success) {
                revert FailedToVerify();
            }
            return UserRequest(routeId, socketRequest);
        } else {
            revert RouteIdNotFound();
        }
    }

    function validateRotueId(
        bytes calldata callData,
        uint32 expectedRouteId
    ) external {
        uint32 routeId = uint32(bytes4(callData[0:4]));
        if (routeIdsToVerifiers[routeId] != address(0)) {
            if (routeId != expectedRouteId) {
                revert RouteIdNotMatched();
            }
        } else {
            revert RouteIdNotFound();
        }
    }

    function validateSocketRequest(
        bytes calldata callData,
        UserRequestValidation calldata expectedRequest
    ) external {
        UserRequest memory userRequest = parseCallData(callData);
        if (userRequest.routeId != expectedRequest.routeId) {
            revert RouteIdNotMatched();
        }

        SocketRequest memory socketRequest = abi.decode(
            userRequest.socketRequest,
            (SocketRequest)
        );

        if (socketRequest.amount != expectedRequest.socketRequest.amount) {
            revert AmountNotMatched();
        }
        if (
            socketRequest.recipient != expectedRequest.socketRequest.recipient
        ) {
            revert RecipientNotMatched();
        }
        if (
            socketRequest.toChainId != expectedRequest.socketRequest.toChainId
        ) {
            revert ToChainIdNotMatched();
        }
        if (socketRequest.token != expectedRequest.socketRequest.token) {
            revert TokenNotMatched();
        }
        if (
            socketRequest.signature != expectedRequest.socketRequest.signature
        ) {
            revert SignatureNotMatched();
        }
    }

    function addVerifier(uint32 routeId, address verifier) external onlyOwner {
        routeIdsToVerifiers[routeId] = verifier;
    }
}

