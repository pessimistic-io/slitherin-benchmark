pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Ownable.sol";
import {ISocket} from "./ISocket.sol";

contract uniERC721 is ERC721, Ownable {
    address public socket;
    uint256 mintedTokenId;

    bool isMintingAllowed;

    mapping(uint256 => uint256) public destGasLimits;

    modifier onlySocket() {
        require(msg.sender == socket, "Msg Sender not Socket");
        _;
    }

    modifier mintingAllowed() {
        require(isMintingAllowed, "Minting not allowed");
        _;
    }

    event TokenMinted(address minter, uint256 tokenId);

    event UniTransfer(
        uint256 destChainSlug,
        address destReceiver,
        uint256 tokenId
    );

    event UniReceive(
        address sender,
        address destReceiver,
        uint256 tokenId,
        uint256 srcChainSlug
    );

    constructor(
        address socket_,
        string memory name_,
        string memory symbol_,
        bool isMintingAllowed_
    ) ERC721(name_, symbol_) {
        isMintingAllowed = isMintingAllowed_;
        socket = socket_;
    }

    /************************************************************************
        Config Functions 
    ************************************************************************/

    function setIsMintingAllowed(bool _val) external onlyOwner {
        isMintingAllowed = _val;
    }

    function setSocketAddress(address _socket) external onlyOwner {
        socket = _socket;
    }

    function setDestChainGasLimit(
        uint256 _chainSlug,
        uint256 _gasLimit
    ) external onlyOwner {
        destGasLimits[_chainSlug] = _gasLimit;
    }

    function connectRemoteNFTToken(
        uint256 siblingChainSlug_,
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

    /************************************************************************
        Minting & Transfering NFT
    ************************************************************************/

    /* Mints token on curernt chain if allowed */
    function mintToken() public mintingAllowed {
        _safeMint(msg.sender, mintedTokenId);
        mintedTokenId++;
        emit TokenMinted(msg.sender, mintedTokenId);
    }

    /* Transfers tokens between chains */
    function uniTransfer(
        uint256 _destChainSlug,
        address _destReceiver,
        uint256 tokenId
    ) external payable {
        _burn(tokenId);

        bytes memory payload = abi.encode(msg.sender, _destReceiver, tokenId);

        ISocket(socket).outbound(
            _destChainSlug,
            destGasLimits[_destChainSlug],
            payload
        );

        emit UniTransfer(_destChainSlug, _destReceiver, tokenId);
    }

    function _uniReceive(
        uint256 _siblingChainSlug,
        address _sender,
        address _receiver,
        uint256 _tokenId
    ) internal {
        _safeMint(_receiver, _tokenId);

        emit UniReceive(_sender, _receiver, _tokenId, _siblingChainSlug);
    }

    /* Called by Socket on destination chain when sending message */
    function inbound(
        uint256 siblingChainSlug_,
        bytes calldata payload_
    ) external onlySocket {
        (address sender, address receiver, uint256 tokenId) = abi.decode(
            payload_,
            (address, address, uint256)
        );
        _uniReceive(siblingChainSlug_, sender, receiver, tokenId);
    }
}

