// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

import "./ERC20.sol";
import "./Ownable.sol";
import "./RescueFundsLib.sol";
import "./ISocket.sol";

contract LootDAI is ERC20, Ownable {
    address public socket;

    event UniTransfer(
        address sender,
        address receiver,
        uint256 amount,
        uint32 destChainSlug
    );

    event UniReceive(
        address sender,
        address receiver,
        uint256 amount,
        uint32 srcChainSlug
    );

    modifier onlySocket() {
        require(msg.sender == socket, "Not authorised");
        _;
    }

    constructor(
        uint256 initialSupply_,
        address socket_
    ) ERC20("Loot DAI", "LDAI") {
        socket = socket_;
        _mint(msg.sender, initialSupply_);
    }

    /************************************************************************
        Config Functions 
    ************************************************************************/

    function connectRemoteToken(
        uint32 siblingChainSlug_,
        address siblingPlug_,
        address inboundSwitchboard_,
        address outboundSwitchboard_
    ) external onlyOwner {
        ISocket(socket).connect(
            siblingChainSlug_,
            siblingPlug_,
            inboundSwitchboard_,
            outboundSwitchboard_
        );
    }

    function setSocketAddress(address socket_) external onlyOwner {
        socket = socket_;
    }

    /************************************************************************
        Cross-chain Token Transfer & Receive 
    ************************************************************************/

    /* Burns user tokens on source chain and sends mint message on destination chain */
    function uniTransfer(
        uint32 destChainSlug_,
        uint256 destGasLimit_,
        address destReceiver_,
        uint256 amount_
    ) external payable {
        _burn(msg.sender, amount_);
        bytes memory payload = abi.encode(msg.sender, destReceiver_, amount_);

        ISocket(socket).outbound{value: msg.value}(
            destChainSlug_,
            destGasLimit_,
            bytes32(0),
            payload
        );

        emit UniTransfer(msg.sender, destReceiver_, amount_, destChainSlug_);
    }

    /* Decodes destination data and mints equivalent tokens burnt on source chain */
    function _uniReceive(
        uint32 siblingChainSlug_,
        bytes calldata payload_
    ) internal {
        (address sender, address receiver, uint256 amount) = abi.decode(
            payload_,
            (address, address, uint256)
        );

        _mint(receiver, amount);
        emit UniReceive(sender, receiver, amount, siblingChainSlug_);
    }

    /* Called by Socket on destination chain when sending message */
    function inbound(
        uint32 siblingChainSlug_,
        bytes calldata payload_
    ) external payable onlySocket {
        _uniReceive(uint32(siblingChainSlug_), payload_);
    }

    function mint(uint256 amount) external onlyOwner {
        _mint(msg.sender, amount);
    }

    function rescueFunds(
        address token_,
        address userAddress_,
        uint256 amount_
    ) external onlyOwner {
        RescueFundsLib.rescueFunds(token_, userAddress_, amount_);
    }
}

