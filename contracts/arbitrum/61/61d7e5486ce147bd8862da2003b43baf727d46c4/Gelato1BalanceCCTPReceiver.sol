// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {     GelatoRelayContext } from "./GelatoRelayContext.sol";
import {     IGelato1BalanceCCTPReceiver } from "./IGelato1BalanceCCTPReceiver.sol";
import {IMessageTransmitter} from "./IMessageTransmitter.sol";
import {IGelato1Balance} from "./IGelato1Balance.sol";
import {IEIP3009Token} from "./IEIP3009Token.sol";
import {Vault, computeVaultAddress} from "./Vault.sol";

contract Gelato1BalanceCCTPReceiver is
    IGelato1BalanceCCTPReceiver,
    GelatoRelayContext
{
    IEIP3009Token public immutable token;
    IGelato1Balance public immutable oneBalance;
    IMessageTransmitter public immutable messageTransmitter;

    // https://developers.circle.com/stablecoins/docs/cctp-technical-reference#message-format
    uint8 private constant _BODY_INDEX = 116;
    uint8 private constant _MINT_RECIPIENT_INDEX = _BODY_INDEX + 36;
    uint8 private constant _AMOUNT_INDEX = _BODY_INDEX + 68;

    constructor(
        IEIP3009Token _token,
        IGelato1Balance _oneBalance,
        IMessageTransmitter _messageTransmitter
    ) {
        token = _token;
        oneBalance = _oneBalance;
        messageTransmitter = _messageTransmitter;
    }

    function receiveAndDeposit(
        address _owner,
        bytes calldata _message,
        bytes calldata _attestation
    ) external onlyGelatoRelay {
        address vault = _getOrCreateVault(_owner);

        _requireVaultIsMintRecipient(vault, _message);
        messageTransmitter.receiveMessage(_message, _attestation);

        uint256 amount = _decodeAmount(_message);
        token.transferFrom(vault, address(this), amount);

        _transferRelayFee();
        uint256 remaining = amount - _getFee();

        /*token.approve(address(oneBalance), remaining);
        oneBalance.depositToken(_owner, token, remaining);*/

        token.transfer(_owner, remaining);
    }

    function receiveAndWithdraw(
        bytes calldata _message,
        bytes calldata _attestation
    ) external {
        address vault = _getOrCreateVault(msg.sender);

        _requireVaultIsMintRecipient(vault, _message);
        messageTransmitter.receiveMessage(_message, _attestation);

        uint256 amount = _decodeAmount(_message);
        token.transferFrom(vault, msg.sender, amount);
    }

    function _getOrCreateVault(
        address _owner
    ) internal returns (address vault) {
        vault = computeVaultAddress(_owner, token, this);
        if (vault.code.length == 0) _deployVault(_owner);
    }

    function _deployVault(address _owner) internal {
        new Vault{salt: keccak256(abi.encodePacked(_owner))}(token);
    }

    function _requireVaultIsMintRecipient(
        address _vault,
        bytes calldata _message
    ) internal pure {
        require(
            _vault == _decodeMintRecipient(_message),
            "Gelato1BalanceCCTPReceiver._requireVaultIsMintRecipient"
        );
    }

    function _decodeMintRecipient(
        bytes calldata _message
    ) internal pure returns (address) {
        bytes32 mintRecipient = bytes32(_message[_MINT_RECIPIENT_INDEX:]);
        return address(uint160(uint256(mintRecipient)));
    }

    function _decodeAmount(
        bytes calldata _message
    ) internal pure returns (uint256) {
        bytes32 amount = bytes32(_message[_AMOUNT_INDEX:]);
        return uint256(amount);
    }
}

