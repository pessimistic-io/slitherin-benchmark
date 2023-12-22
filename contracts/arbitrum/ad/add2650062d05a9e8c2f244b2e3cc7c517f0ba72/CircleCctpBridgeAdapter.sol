// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";

import {IMessageHandler} from "./IMessageHandler.sol";
import {IMessageTransmitter} from "./IMessageTransmitter.sol";
import {ITokenMessenger} from "./ITokenMessenger.sol";

import {BridgeAdapter} from "./BridgeAdapter.sol";

struct CircleDomain {
    uint256 chainId;
    uint32 domain;
}

contract CircleCctpBridgeAdapter is BridgeAdapter, IMessageHandler {
    ITokenMessenger immutable _tokenMessenger;
    IMessageTransmitter immutable _messageTransmitter;
    IERC20 immutable _usdc;
    bytes32 immutable _selfAddress;

    mapping(uint256 => uint32) _domains;

    constructor(
        address usdc_,
        address tokenMessenger_,
        address messageTransmitter_,
        CircleDomain[] memory circleDomains
    ) {
        _usdc = IERC20(usdc_);
        _selfAddress = bytes32(uint256(uint160(address(this))));

        _tokenMessenger = ITokenMessenger(tokenMessenger_);
        _messageTransmitter = IMessageTransmitter(messageTransmitter_);

        for (uint256 i = 0; i < circleDomains.length; i++) {
            _domains[circleDomains[i].chainId] = circleDomains[i].domain;
        }
    }

    function bridgeToken(
        GeneralParams calldata generalParams,
        SendTokenParams calldata sendTokenParams
    ) external payable {
        // we can't remove payable modifier, so we added this check
        require(msg.value == 0);
        if (sendTokenParams.token != address(_usdc))
            revert UnsupportedToken(sendTokenParams.token);

        uint32 destinationDomain = _domains[generalParams.chainId];
        if (block.chainid != 1 && destinationDomain == 0) {
            // for chainId 0 (Ethereum) Cirlce domain is 0
            // so we manually ignore default mapping value
            // in Ethereum
            revert UnsupportedChain(generalParams.chainId);
        }

        _usdc.approve(address(_tokenMessenger), sendTokenParams.amount);

        _tokenMessenger.depositForBurnWithCaller(
            sendTokenParams.amount,
            destinationDomain,
            _selfAddress,
            address(_usdc),
            _selfAddress
        );
        _messageTransmitter.sendMessageWithCaller(
            destinationDomain,
            _selfAddress,
            _selfAddress,
            _generatePayload(
                _generateTraceId(),
                generalParams.fundsCollector,
                generalParams.withdrawalAddress,
                generalParams.owner,
                sendTokenParams.amount
            )
        );
    }

    function handleReceiveMessage(
        uint32,
        bytes32 messageSender,
        bytes calldata messageBody
    ) external returns (bool) {
        require(messageSender == _selfAddress);

        (
            bytes32 traceId,
            address fundsCollector,
            address withdrawalAddress,
            address owner,
            uint256 amount
        ) = _parsePayload(messageBody);

        _finishBridgeToken(
            traceId,
            address(_usdc),
            amount,
            fundsCollector,
            withdrawalAddress,
            owner
        );
        return true;
    }

    function receiveBurnAndBridgeMessages(
        bytes calldata burnMessage,
        bytes calldata bridgeMessage,
        bytes calldata burnAttestation,
        bytes calldata bridgeAttestation
    ) external {
        _messageTransmitter.receiveMessage(burnMessage, burnAttestation);
        _messageTransmitter.receiveMessage(bridgeMessage, bridgeAttestation);
    }

    function estimateBridgeFee(
        GeneralParams calldata,
        SendTokenParams calldata
    ) external pure returns (uint256) {
        return 0;
    }

    function _generatePayload(
        bytes32 traceId,
        address fundsCollector,
        address withdrawalAddress,
        address owner,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                traceId,
                fundsCollector,
                withdrawalAddress,
                owner,
                amount
            );
    }

    function _parsePayload(
        bytes calldata payload
    )
        internal
        pure
        returns (
            bytes32 traceId,
            address fundsCollector,
            address withdrawalAddress,
            address owner,
            uint256 amount
        )
    {
        (traceId, fundsCollector, withdrawalAddress, owner, amount) = abi
            .decode(payload, (bytes32, address, address, address, uint256));
    }
}

