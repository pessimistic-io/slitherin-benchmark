// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";

import {IMessageHandler} from "./IMessageHandler.sol";
import {IMessageTransmitter} from "./IMessageTransmitter.sol";
import {ITokenMessenger} from "./ITokenMessenger.sol";
import {BridgeAdapter} from "./BridgeAdapter.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";

struct CircleDomain {
    uint256 chainId;
    uint32 domain;
}

contract CircleCctpBridgeAdapter is
    IBridgeAdapter,
    BridgeAdapter,
    IMessageHandler
{
    ITokenMessenger immutable _TOKEN_MESSENGER;
    IMessageTransmitter immutable _MESSAGE_TRANSMITTER;
    IERC20 immutable _USDC;
    bytes32 immutable _SELF;

    mapping(uint256 => uint32) _domains;

    constructor(
        address usdc_,
        address tokenMessenger_,
        address messageTransmitter_,
        CircleDomain[] memory circleDomains
    ) {
        _USDC = IERC20(usdc_);
        _USDC.approve(tokenMessenger_, type(uint256).max);

        _SELF = bytes32(uint256(uint160(address(this))));

        _TOKEN_MESSENGER = ITokenMessenger(tokenMessenger_);
        _MESSAGE_TRANSMITTER = IMessageTransmitter(messageTransmitter_);

        // we store domain+1 because Ethereum Mainnet/Goerli domain = 0,
        // but also default value from mapping is 0
        for (uint256 i = 0; i < circleDomains.length; i++) {
            _domains[circleDomains[i].chainId] = circleDomains[i].domain + 1;
        }
    }

    function receiveBurnAndBridgeMessages(
        bytes calldata mintMessage,
        bytes calldata bridgeMessage,
        bytes calldata mintAttestation,
        bytes calldata bridgeAttestation
    ) external {
        _MESSAGE_TRANSMITTER.receiveMessage(mintMessage, mintAttestation);
        _MESSAGE_TRANSMITTER.receiveMessage(bridgeMessage, bridgeAttestation);
    }

    // solhint-disable-next-line named-return-values
    function handleReceiveMessage(
        uint32,
        bytes32 messageSender,
        bytes calldata messageBody
    ) external returns (bool) {
        if (messageSender != _SELF) revert Unauthorized();

        (uint256 amount, bytes memory payload) = abi.decode(
            messageBody,
            (uint256, bytes)
        );
        _finishBridge(address(_USDC), amount, payload);

        return true;
    }

    /// @inheritdoc IBridgeAdapter
    function estimateFee(
        Token calldata,
        Message calldata
    ) external pure returns (uint256 fee) {
        fee = 0;
    }

    function _startBridge(
        Token calldata token,
        Message calldata message,
        bytes32 traceId
    ) internal override {
        // we can't remove payable modifier, so we added this check
        require(msg.value == 0);
        if (token.address_ != address(_USDC))
            revert UnsupportedToken(token.address_);

        uint32 destinationDomain = _domains[message.dstChainId];
        if (destinationDomain == 0) {
            revert UnsupportedChain(message.dstChainId);
        }
        destinationDomain -= 1;

        _TOKEN_MESSENGER.depositForBurnWithCaller({
            amount: token.amount,
            destinationDomain: destinationDomain,
            mintRecipient: _SELF,
            burnToken: address(_USDC),
            destinationCaller: _SELF
        });
        _MESSAGE_TRANSMITTER.sendMessageWithCaller(
            destinationDomain,
            _SELF,
            _SELF,
            abi.encode(
                token.amount,
                _generatePayload(traceId, msg.sender, message.content)
            )
        );
    }
}

