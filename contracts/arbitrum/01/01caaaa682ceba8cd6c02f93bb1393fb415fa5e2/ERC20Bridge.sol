//SPDX-License-Identifier: MIT
import "./NonblockingLzApp.sol";
import "./ERC20BridgeRateLimiter.sol";

pragma solidity 0.8.17;

contract ERC20Bridge is NonblockingLzApp, ERC20BridgeRateLimiter {

    // Structs
    struct MintMessage {
        address to;
        uint amount;
    }

    // Events
    event MintMessageReceived(uint16 indexed srcChainId, address indexed to, uint amount);
    event BridgingInitiated(uint16 indexed targetChainId, address indexed to, uint amount);

    constructor(
        address _lzEndpoint,
        IERC20MintableBurnable _token,
        address _owner,
        uint _maxEpochLimit,
        uint _epochDuration,
        uint _epochLimit
    ) NonblockingLzApp(_lzEndpoint) ERC20BridgeRateLimiter(
        _token,
        _owner,
        _maxEpochLimit,
        _epochDuration,
        _epochLimit
    ) {}

    // @dev Helper to build MintMessage
    function buildBridgeMessage(address to, uint amount) private pure returns (bytes memory) {
        return abi.encode(
            MintMessage({
                to: to,
                amount: amount
            })
        );
    }

    // @notice Mints GNS bridged from the other side, can only be invoked by a trusted remote
    // @param payload message sent from the other side
    function _nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory /* srcAddress */,
        uint64 /* nonce */,
        bytes memory payload
    ) internal override {
        MintMessage memory message = abi.decode(payload, (MintMessage));
        
        if(paused()){
            addPendingClaim(message.to, message.amount);
        }else{
            tryMint(message.to, message.amount);
        }
        
        emit MintMessageReceived(srcChainId, message.to, message.amount);
    }

    // @notice Burns GNS from caller, then sends a cross-chain message to the destination chain.
    // @param dstChainId The **LayerZero** destination chain ID.
    function bridgeTokens(uint16 dstChainId, uint amount) external payable whenNotPaused {
        require(msg.value != 0, "!fee");
        require(amount > 0, "!amount");

        address sender = _msgSender();
        tryBurn(sender, amount);

        _lzSend(
            dstChainId,
            buildBridgeMessage(sender, amount),
            payable(sender),  // refund address (LayerZero will refund any extra gas back to caller)
            address(0x0),     // unused
            bytes(""),        // unused
            msg.value         // native fee amount
        );

        emit BridgingInitiated(dstChainId, sender, amount);
    }

    // @notice Used by the frontend to estimate how much native token should be sent with bridgeTokens() for LayerZero fees.
    // @param dstChainId The **LayerZero** destination chain ID.
    function estimateNativeFee(
        uint16 dstChainId,
        address to,
        uint amount
    ) external view returns (uint nativeFee) {
        (nativeFee, ) = lzEndpoint.estimateFees(
            dstChainId,
            address(this),
            buildBridgeMessage(to, amount),
            false,
            bytes("")
        );
    }
}

