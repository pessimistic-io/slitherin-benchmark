// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./EnumerableMap.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

import "./IFactorMsgSendEndpoint.sol";

/**
 * @notice This abstract is a modified version of Pendle's PendleMsgSenderAppUpg.sol:
 * https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/LiquidityMining
 * /CrossChainMsg/PendleMsgSenderAppUpg.sol
 *
 */

// solhint-disable no-empty-blocks

abstract contract FactorMsgSenderUpgradeable is OwnableUpgradeable {
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    struct FactorMsgSenderStorage {
        uint256 approxDstExecutionGas;
        address factorMsgSendEndpoint;
        EnumerableMap.UintToAddressMap destinationContracts;
    }

    bytes32 private constant MSG_SENDER_STORAGE = keccak256('factor.crosschain.MsgSenderStorage');

    function _getMsgSenderStorage() internal pure returns (FactorMsgSenderStorage storage $) {
        bytes32 slot = MSG_SENDER_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    error InsufficientFeeToSendMsg(uint256 currentFee, uint256 requiredFee);

    modifier refundUnusedEth() {
        _;
        if (address(this).balance > 0) {
            (bool success, ) = payable(msg.sender).call{ value: address(this).balance }('');
            require(success, 'Address: unable to send value, recipient may have reverted');
        }
    }

    function __FactorMsgSender_init(
        address _factorMsgSendEndpoint,
        uint256 _approxDstExecutionGas
    ) internal onlyInitializing {
        _getMsgSenderStorage().factorMsgSendEndpoint = _factorMsgSendEndpoint;
        _getMsgSenderStorage().approxDstExecutionGas = _approxDstExecutionGas;
    }

    function _sendMessage(uint256 chainId, bytes memory message) internal {
        FactorMsgSenderStorage storage $ = _getMsgSenderStorage();
        assert($.destinationContracts.contains(chainId));
        address toAddr = $.destinationContracts.get(chainId);
        uint256 estimatedGasAmount = $.approxDstExecutionGas;
        uint256 fee = IFactorMsgSendEndpoint($.factorMsgSendEndpoint).calcFee(
            toAddr,
            chainId,
            message,
            estimatedGasAmount
        );
        // LM contracts won't hold ETH on its own so this is fine
        if (address(this).balance < fee) revert InsufficientFeeToSendMsg(address(this).balance, fee);
        IFactorMsgSendEndpoint($.factorMsgSendEndpoint).sendMessage{ value: fee }(
            toAddr,
            chainId,
            message,
            estimatedGasAmount
        );
    }

    function addDestinationContract(address _address, uint256 _chainId) external payable onlyOwner {
        _getMsgSenderStorage().destinationContracts.set(_chainId, _address);
    }

    function setApproxDstExecutionGas(uint256 gas) external onlyOwner {
        _getMsgSenderStorage().approxDstExecutionGas = gas;
    }

    function getAllDestinationContracts() public view returns (uint256[] memory chainIds, address[] memory addrs) {
        FactorMsgSenderStorage storage $ = _getMsgSenderStorage();
        uint256 length = $.destinationContracts.length();
        chainIds = new uint256[](length);
        addrs = new address[](length);

        for (uint256 i = 0; i < length; ++i) {
            (chainIds[i], addrs[i]) = $.destinationContracts.at(i);
        }
    }

    function _getSendMessageFee(uint256 chainId, bytes memory message) internal view returns (uint256) {
        FactorMsgSenderStorage storage $ = _getMsgSenderStorage();
        return
            IFactorMsgSendEndpoint($.factorMsgSendEndpoint).calcFee(
                $.destinationContracts.get(chainId),
                chainId,
                message,
                $.approxDstExecutionGas
            );
    }

    function approxDstExecutionGas() public view returns (uint256) {
        return _getMsgSenderStorage().approxDstExecutionGas;
    }

    function factorMsgSendEndpoint() public view returns (address) {
        return _getMsgSenderStorage().factorMsgSendEndpoint;
    }
}

