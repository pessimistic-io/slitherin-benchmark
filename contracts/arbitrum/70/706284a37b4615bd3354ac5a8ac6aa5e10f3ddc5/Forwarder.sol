// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "./IERC20.sol";
import {ITokenMessenger} from "./ITokenMessenger.sol";
import {IMessageTransmitter} from "./IMessageTransmitter.sol";
import {GelatoRelayContext} from "./GelatoRelayContext.sol";

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
    ) external onlyGelatoRelayERC2771 {
        address owner = abi.decode(receiveAuthorization, (address));
        require(
            _getMsgSender() == owner,
            "Forwarder.deposit: signer must be authorizer"
        );

        _receiveWithAuthorization(receiveAuthorization);
        _transferRelayFeeCappedERC2771(maxFee);

        uint256 remaining = token.balanceOf(address(this));
        token.approve(address(tokenMessenger), remaining);

        tokenMessenger.depositForBurn(
            remaining,
            destinationDomain,
            _addressToBytes32(owner),
            address(token)
        );
    }

    function withdraw(
        bytes calldata message,
        bytes calldata attestation,
        bytes calldata receiveAuthorization
    ) external onlyGelatoRelay {
        messageTransmitter.receiveMessage(message, attestation);

        _receiveWithAuthorization(receiveAuthorization);
        _transferRelayFee();

        address owner = abi.decode(receiveAuthorization, (address));
        uint256 remaining = token.balanceOf(address(this));

        token.transfer(owner, remaining);
    }

    function _receiveWithAuthorization(bytes calldata authorization) internal {
        _requireCall(
            address(token),
            abi.encodePacked(bytes4(0xef55bec6), authorization)
        );
    }

    function _requireCall(address target, bytes memory data) internal {
        (bool success, bytes memory result) = address(target).call(data);
        assembly {
            if eq(success, false) {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}

