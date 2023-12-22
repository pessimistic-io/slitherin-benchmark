// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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
        _usdc.approve(tokenMessenger_, type(uint256).max);

        _selfAddress = bytes32(uint256(uint160(address(this))));

        _tokenMessenger = ITokenMessenger(tokenMessenger_);
        _messageTransmitter = IMessageTransmitter(messageTransmitter_);

        // we store domain+1 because Ethereum Mainnet/Goerli domain = 0,
        // but also default value from mapping is 0
        for (uint256 i = 0; i < circleDomains.length; i++) {
            _domains[circleDomains[i].chainId] = circleDomains[i].domain + 1;
        }
    }

    function sendTokenWithMessage(
        Token calldata token,
        Message calldata message
    ) external payable {
        // we can't remove payable modifier, so we added this check
        require(msg.value == 0);
        if (token.address_ != address(_usdc))
            revert UnsupportedToken(token.address_);

        uint32 destinationDomain = _domains[message.dstChainId];
        if (destinationDomain == 0) {
            revert UnsupportedChain(message.dstChainId);
        }
        destinationDomain -= 1;

        _tokenMessenger.depositForBurnWithCaller(
            token.amount,
            destinationDomain,
            _selfAddress,
            address(_usdc),
            _selfAddress
        );
        _messageTransmitter.sendMessageWithCaller(
            destinationDomain,
            _selfAddress,
            _selfAddress,
            abi.encode(
                token.amount,
                _generatePayload(
                    _generateTraceId(),
                    msg.sender,
                    message.content
                )
            )
        );
    }

    function handleReceiveMessage(
        uint32,
        bytes32 messageSender,
        bytes calldata messageBody
    ) external returns (bool) {
        require(messageSender == _selfAddress);

        (uint256 amount, bytes memory payload) = abi.decode(
            messageBody,
            (uint256, bytes)
        );
        _finishBridgeToken(address(_usdc), amount, payload);

        return true;
    }

    function receiveBurnAndBridgeMessages(
        bytes calldata mintMessage,
        bytes calldata bridgeMessage,
        bytes calldata mintAttestation,
        bytes calldata bridgeAttestation
    ) external {
        _messageTransmitter.receiveMessage(mintMessage, mintAttestation);
        _messageTransmitter.receiveMessage(bridgeMessage, bridgeAttestation);
    }

    function estimateFee(
        Token calldata,
        Message calldata
    ) external pure returns (uint256) {
        return 0;
    }
}

