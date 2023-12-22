//SPDX-License-Identifier: MIT
import "./NonblockingLzApp.sol";
import "./ERC721BridgeRateLimiter.sol";

pragma solidity 0.8.17;

abstract contract ERC721Bridge is NonblockingLzApp, ERC721BridgeRateLimiter{
    
    // Structs
    struct UnlockMessage {
        address to;
        NftTier nftTier;
        uint tokenId;
    }

    // Events
    event UnlockMessageReceived(uint16 indexed srcChainId, address indexed to, NftTier nftTier, uint indexed tokenId);
    event BridgingInitiated(uint16 indexed dstChainId, address indexed from, NftTier nftTier, uint indexed tokenId);

    constructor(
        address _lzEndpoint,
        IERC721[5] memory _nfts,
        address _owner,
        uint _maxEpochLimit,
        uint _epochDuration,
        uint _epochLimit
    ) NonblockingLzApp(_lzEndpoint) ERC721BridgeRateLimiter(
        _nfts,
        _owner,
        _maxEpochLimit,
        _epochDuration,
        _epochLimit
    ) {}

    // @dev Helper to build UnlockMessage
    function buildBridgeMessage(
        address to,
        NftTier nftTier,
        uint tokenId
    ) private pure returns (bytes memory) {
        return abi.encode(
            UnlockMessage({
                to: to,
                nftTier: nftTier,
                tokenId: tokenId
            })
        );
    }

    // @dev Unlocks an NFT bridged from the other side, can only be invoked by a trusted remote
    // @param payload message sent from the other side
    function _nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory /* srcAddress */,
        uint64 /* nonce */,
        bytes memory payload
    ) internal override {
        UnlockMessage memory message = abi.decode(payload, (UnlockMessage));

        if(paused()){
            addPendingClaim(message.to, message.nftTier, message.tokenId);
        }else{
            tryUnlockNft(message.to, message.nftTier, message.tokenId);
        }
        
        emit UnlockMessageReceived(srcChainId, message.to, message.nftTier, message.tokenId);
    }

    // @notice Locks an NFT from caller, then sends a cross-chain message to the destination chain.
    // @param dstChainId The **LayerZero** destination chain ID.
    function bridgeNft(uint16 dstChainId, NftTier nftTier, uint tokenId) external payable whenNotPaused {

        // Make sure a native fee is supplied for the cross-chain message.
        require(msg.value != 0, "!fee");

        address sender = _msgSender();
        tryLockNft(sender, nftTier, tokenId);

        _lzSend(
            dstChainId,
            buildBridgeMessage(sender, nftTier, tokenId),
            payable(sender),  // refund address (LayerZero will refund any extra gas back to caller)
            address(0x0),     // unused
            bytes(""),        // unused
            msg.value         // native fee amount
        );

        emit BridgingInitiated(dstChainId, sender, nftTier, tokenId);
    }

    // @notice Used by the frontend to estimate how much native token to send with bridgeNft() for LayerZero fees.
    // @param dstChainId The **LayerZero** destination chain ID.
    function estimateNativeFee(
        uint16 dstChainId,
        address to,
        NftTier nftTier,
        uint tokenId
    ) external view returns (uint nativeFee) {
        (nativeFee, ) = lzEndpoint.estimateFees(
            dstChainId,
            address(this),
            buildBridgeMessage(to, nftTier, tokenId),
            false,
            bytes("")
        );
    }
}
