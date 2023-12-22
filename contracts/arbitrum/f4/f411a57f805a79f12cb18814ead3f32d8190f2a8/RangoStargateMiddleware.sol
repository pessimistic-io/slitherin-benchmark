// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./LibInterchain.sol";
import "./ReentrancyGuard.sol";
import "./RangoBaseInterchainMiddleware.sol";

/// @title The middleware contract that handles Rango's receive messages from stargate.
/// @author George
/// @dev Note that this is not a facet and should be deployed separately.
contract RangoStargateMiddleware is ReentrancyGuard, IStargateReceiver, RangoBaseInterchainMiddleware {

    /// @dev keccak256("exchange.rango.middleware.stargate")
    bytes32 internal constant STARGATE_MIDDLEWARE_NAMESPACE = hex"8f95700cb6d0d3fbe23970b0fed4ae8d3a19af1ff9db49b72f280b34bdf7bad8";

    struct RangoStargateMiddlewareStorage {
        address stargateRouter;
    }

    constructor(
        address _owner,
        address _stargateRouter,
        address _weth
    ) RangoBaseInterchainMiddleware(_owner, address(0), _weth){
        updateStargateRouterAddressInternal(_stargateRouter);
    }

    /// Events

    /// @notice Emits when the Stargate address is updated
    /// @param oldAddress The previous address
    /// @param newAddress The new address
    event StargateRouterAddressUpdated(address oldAddress, address newAddress);
    /// @notice A series of events with different status value to help us track the progress of cross-chain swap
    /// @param token The token address in the current network that is being bridged
    /// @param outputAmount The latest observed amount in the path, aka: input amount for source and output amount on dest
    /// @param status The latest status of the overall flow
    /// @param source The source address that initiated the transaction
    /// @param destination The destination address that received the money, ZERO address if not sent to the end-user yet
    event StargateSwapStatusUpdated(
        address token,
        uint256 outputAmount,
        IRango.CrossChainOperationStatus status,
        address source,
        address destination
    );

    /// External Functions

    /// @notice Updates the address of stargateRouter
    /// @param newAddress The new address of owner
    function updateStargateRouter(address newAddress) external onlyOwner {
        updateStargateRouterAddressInternal(newAddress);
    }

    // @param _chainId The remote chainId sending the tokens
    // @param _srcAddress The remote Bridge address
    // @param _nonce The message ordering nonce
    // @param _token The token contract on the local chain
    // @param amountLD The qty of local _token contract tokens
    // @param _payload The bytes containing the _tokenOut, _deadline, _amountOutMin, _toAddr
    function sgReceive(
        uint16,
        bytes memory,
        uint256,
        address _token,
        uint256 amountLD,
        bytes memory payload
    ) external override nonReentrant {
        require(msg.sender == getRangoStargateMiddlewareStorage().stargateRouter,
            "sgReceive function can only be called by Stargate router");
        Interchain.RangoInterChainMessage memory m = abi.decode((payload), (Interchain.RangoInterChainMessage));
        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(_token, amountLD, m);

        emit StargateSwapStatusUpdated(receivedToken, dstAmount, status, m.originalSender, m.recipient);
    }

    /// Private and Internal
    function updateStargateRouterAddressInternal(address newAddress) private {
        RangoStargateMiddlewareStorage storage s = getRangoStargateMiddlewareStorage();
        address oldAddress = s.stargateRouter;
        s.stargateRouter = newAddress;
        emit StargateRouterAddressUpdated(oldAddress, newAddress);
    }

    /// @dev fetch local storage
    function getRangoStargateMiddlewareStorage() private pure returns (RangoStargateMiddlewareStorage storage s) {
        bytes32 namespace = STARGATE_MIDDLEWARE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
