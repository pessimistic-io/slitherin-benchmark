// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./ISocket.sol";

abstract contract PlugBaseInitializable {
    address public owner;
    ISocket public socket;
    bool public initialized;

    error AlreadyInitialized();

    function _initialize(address socket_) internal {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        owner = msg.sender;
        socket = ISocket(socket_);
    }

    //
    // Modifiers
    //
    modifier onlyOwner() {
        require(msg.sender == owner, "no auth");
        _;
    }

    function connect(
        uint256 siblingChainSlug_,
        address siblingPlug_,
        address inboundSwitchboard_,
        address outboundSwitchboard_
    ) external onlyOwner {
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

    // owner related functions

    function removeOwner() external onlyOwner {
        owner = address(0);
    }
}

