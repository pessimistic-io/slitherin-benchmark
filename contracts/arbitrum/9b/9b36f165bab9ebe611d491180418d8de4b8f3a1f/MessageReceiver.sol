// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

import "./Ownable.sol";
import "./IBridge.sol";
import "./MsgReceiverApp.sol";

contract MessageReceiver is Ownable {
    enum TransferType {
        Null,
        LqSend, // send through liquidity bridge
        LqWithdraw, // withdraw from liquidity bridge
        PegMint, // mint through pegged token bridge
        PegWithdraw // withdraw from original token vault
    }

    struct TransferInfo {
        TransferType t;
        address sender;
        address receiver;
        address token;
        uint256 amount;
        uint64 seqnum;
        uint64 srcChainId;
        bytes32 refId;
    }

    struct RouteInfo {
        address sender;
        address receiver;
        uint64 srcChainId;
    }

    enum TxStatus {
        Null,
        Success,
        Fail,
        Fallback
    }
    mapping(bytes32 => TxStatus) public executedTransfers; // messages with associated transfer
    mapping(bytes32 => TxStatus) public executedMessages; // messages without associated transfer

    address public liquidityBridge; // liquidity bridge address
    address public pegBridge; // peg bridge address
    address public pegVault; // peg original vault address

    enum MsgType {
        MessageWithTransfer,
        Message
    }
    event Executed(MsgType msgType, bytes32 id, TxStatus status);

    // ============== functions called by executor ==============

    function executeMessageWithTransfer(
        bytes calldata _message,
        TransferInfo calldata _transfer,
        bytes[] calldata _sigs,
        address[] calldata _signers,
        uint256[] calldata _powers
    ) external {
        bytes32 transferId = verifyTransfer(_transfer);
        require(executedTransfers[transferId] == TxStatus.Null, "transfer already executed");

        bytes32 domain = keccak256(abi.encodePacked(block.chainid, address(this), "MessageWithTransfer"));
        IBridge(liquidityBridge).verifySigs(abi.encodePacked(domain, transferId, _message), _sigs, _signers, _powers);
        TxStatus status;
        bool ok = executeMessageWithTransfer(_transfer, _message);
        if (ok) {
            status = TxStatus.Success;
        } else {
            ok = executeMessageWithTransferFallback(_transfer, _message);
            if (ok) {
                status = TxStatus.Fallback;
            } else {
                status = TxStatus.Fail;
            }
        }
        executedTransfers[transferId] = status;
        emit Executed(MsgType.MessageWithTransfer, transferId, status);
    }

    function executeMessage(
        bytes calldata _message,
        RouteInfo calldata _route,
        bytes[] calldata _sigs,
        address[] calldata _signers,
        uint256[] calldata _powers
    ) external {
        bytes32 messageId = ComputeMessageId(_route, _message);
        require(executedMessages[messageId] == TxStatus.Null, "message already executed");

        bytes32 domain = keccak256(abi.encodePacked(block.chainid, address(this), "Message"));
        IBridge(liquidityBridge).verifySigs(abi.encodePacked(domain, messageId), _sigs, _signers, _powers);
        TxStatus status;
        bool ok = executeMessage(_route, _message);
        if (ok) {
            status = TxStatus.Success;
        } else {
            status = TxStatus.Fail;
        }
        executedTransfers[messageId] = status;
        emit Executed(MsgType.Message, messageId, status);
    }

    // ================= utils (to avoid stack too deep) =================

    function executeMessageWithTransfer(TransferInfo calldata _transfer, bytes calldata _message)
        private
        returns (bool)
    {
        (bool ok, ) = address(_transfer.receiver).call(
            abi.encodeWithSelector(
                MsgReceiverApp.executeMessageWithTransfer.selector,
                _transfer.sender,
                _transfer.token,
                _transfer.amount,
                _transfer.srcChainId,
                _message
            )
        );
        return ok;
    }

    function executeMessageWithTransferFallback(TransferInfo calldata _transfer, bytes calldata _message)
        private
        returns (bool)
    {
        (bool ok, ) = address(_transfer.receiver).call(
            abi.encodeWithSelector(
                MsgReceiverApp.executeMessageWithTransferFallback.selector,
                _transfer.sender,
                _transfer.token,
                _transfer.amount,
                _transfer.srcChainId,
                _message
            )
        );
        return ok;
    }

    function verifyTransfer(TransferInfo calldata _transfer) private view returns (bytes32) {
        bytes32 transferId;
        address bridgeAddr;
        if (_transfer.t == TransferType.LqSend) {
            transferId = keccak256(
                abi.encodePacked(
                    _transfer.sender,
                    _transfer.receiver,
                    _transfer.token,
                    _transfer.amount,
                    _transfer.srcChainId,
                    uint64(block.chainid),
                    _transfer.refId
                )
            );
            bridgeAddr = liquidityBridge;
            require(IBridge(bridgeAddr).transfers(transferId) == true, "bridge relay not exist");
        } else if (_transfer.t == TransferType.LqWithdraw) {
            transferId = keccak256(
                abi.encodePacked(
                    uint64(block.chainid),
                    _transfer.seqnum,
                    _transfer.receiver,
                    _transfer.token,
                    _transfer.amount
                )
            );
            bridgeAddr = liquidityBridge;
            require(IBridge(bridgeAddr).withdraws(transferId) == true, "bridge withdraw not exist");
        } else if (_transfer.t == TransferType.PegMint || _transfer.t == TransferType.PegWithdraw) {
            transferId = keccak256(
                abi.encodePacked(
                    _transfer.receiver,
                    _transfer.token,
                    _transfer.amount,
                    _transfer.sender,
                    _transfer.srcChainId,
                    _transfer.refId
                )
            );
            if (_transfer.t == TransferType.PegMint) {
                bridgeAddr = pegBridge;
            } else {
                bridgeAddr = pegVault;
            }
            require(IBridge(bridgeAddr).records(transferId) == true, "peg record not exist");
        }
        transferId = keccak256(abi.encodePacked(bridgeAddr, transferId));
        return transferId;
    }

    function ComputeMessageId(RouteInfo calldata _route, bytes calldata _message) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_route.sender, _route.receiver, _route.srcChainId, _message));
    }

    function executeMessage(RouteInfo calldata _route, bytes calldata _message) private returns (bool) {
        (bool ok, ) = address(_route.receiver).call(
            abi.encodeWithSelector(MsgReceiverApp.executeMessage.selector, _route.sender, _route.srcChainId, _message)
        );
        return ok;
    }

    // ================= contract addr config =================

    function setLiquidityBridge(address _addr) public onlyOwner {
        liquidityBridge = _addr;
    }

    function setPegBridge(address _addr) public onlyOwner {
        pegBridge = _addr;
    }

    function setPegVault(address _addr) public onlyOwner {
        pegVault = _addr;
    }
}

