// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

import "./ISocket.sol";

abstract contract PlugBase {
    ISocket public socket;

    constructor(address socket_) {
        socket = ISocket(socket_);
    }

    function connect(
        uint256 siblingChainSlug_,
        address siblingPlug_,
        address inboundSwitchboard_,
        address outboundSwitchboard_
    ) external {
        socket.connect(
            siblingChainSlug_,
            siblingPlug_,
            inboundSwitchboard_,
            outboundSwitchboard_
        );
    }

    function inbound(
        uint256 siblingChainSlug_,
        bytes calldata payload_
    ) external payable {
        require(msg.sender == address(socket), "no auth");
        _receiveInbound(siblingChainSlug_, payload_);
    }

    function _outbound(
        uint256 chainSlug_,
        uint256 gasLimit_,
        uint256 fees_,
        bytes memory payload_
    ) internal {
        socket.outbound{value: fees_}(chainSlug_, gasLimit_, payload_);
    }

    function _receiveInbound(
        uint256 siblingChainSlug_,
        bytes memory payload_
    ) internal virtual;

    function _getChainSlug() internal view returns (uint256) {
        return socket.chainSlug();
    }
}

contract ConnectItPlug is PlugBase {
    bool public msgArrived;
    address public sender;

    ISocket public socket__;
    error AlreadySet();

    constructor(address socket_) PlugBase(socket_) {}

    function setRemote(
        uint256 toChainSlug_,
        uint256 dstGasLimit_
    ) external payable {
        _setRemoteState(toChainSlug_, dstGasLimit_, abi.encode(msg.sender));
    }

    function _setRemoteState(
        uint256 toChainSlug_,
        uint256 dstGasLimit_,
        bytes memory data
    ) internal {
        _outbound(toChainSlug_, dstGasLimit_, msg.value, data);
    }

    function _receiveInbound(
        uint256,
        bytes memory data
    ) internal virtual override {
        sender = abi.decode(data, (address));
        msgArrived = true;
    }
}

