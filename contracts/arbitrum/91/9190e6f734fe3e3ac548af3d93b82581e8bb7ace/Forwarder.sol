// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "./IERC20.sol";
import {ITokenMessenger} from "./ITokenMessenger.sol";
import {IMessageTransmitter} from "./IMessageTransmitter.sol";
import {     GelatoRelayContext } from "./GelatoRelayContext.sol";

contract Forwarder is GelatoRelayContext {
    IERC20 public immutable token;
    ITokenMessenger public immutable tokenMessenger;
    IMessageTransmitter public immutable messageTransmitter;

    constructor(
        IERC20 _token,
        ITokenMessenger _tokenMessenger,
        IMessageTransmitter _messageTransmitter
    ) {
        token = _token;
        tokenMessenger = _tokenMessenger;
        messageTransmitter = _messageTransmitter;
    }

    function deposit(
        uint256 maxFee,
        uint32 destinationDomain,
        bytes calldata receiveAuthorization
    ) external onlyGelatoRelay {
        (bool success, bytes memory result) = address(token).call(abi.encodePacked(
            bytes4(0xef55bec6), // receiveWithAuthorization
            receiveAuthorization
        ));

        assembly {
            if eq(success, false) {
                revert(add(result, 32), mload(result))
            }
        }

        _transferRelayFeeCapped(maxFee);

        uint256 remaining = token.balanceOf(address(this));
        token.approve(address(tokenMessenger), remaining);

        bytes32 owner = abi.decode(receiveAuthorization[0:32], (bytes32));

        tokenMessenger.depositForBurn(
            remaining,
            destinationDomain,
            owner,
            address(token)
        );
    }

    function withdraw(
        bytes calldata message,
        bytes calldata attestation,
        bytes calldata receiveAuthorization
    ) external onlyGelatoRelay {
        messageTransmitter.receiveMessage(message, attestation);

        (bool success, bytes memory result) = address(token).call(abi.encodePacked(
            bytes4(0xef55bec6), // receiveWithAuthorization
            receiveAuthorization
        ));

        assembly {
            if eq(success, false) {
                revert(add(result, 32), mload(result))
            }
        }

        _transferRelayFee();

        address owner = abi.decode(receiveAuthorization[0:32], (address));
        uint256 remaining = token.balanceOf(address(this));
        token.transfer(owner, remaining);
    }
}

