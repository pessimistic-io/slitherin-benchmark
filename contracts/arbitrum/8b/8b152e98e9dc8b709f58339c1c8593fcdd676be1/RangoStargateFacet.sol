// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./IUniswapV2.sol";
import "./IWETH.sol";
import "./IRangoStargate.sol";
import "./IStargateReceiver.sol";
import "./Interchain.sol";
import "./LibInterchain.sol";
import "./IRangoMessageReceiver.sol";
import "./IRango.sol";
import "./ReentrancyGuard.sol";
import "./LibDiamond.sol";

/// @title The root contract that handles Rango's interaction with Stargate and receives message from layerZero
/// @author Uchiha Sasuke
contract RangoStargateFacet is IRango, ReentrancyGuard, IRangoStargate, IStargateReceiver {
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.stargate")
    bytes32 internal constant STARGATE_NAMESPACE = hex"9226eefa91acf770d80880f45d613abe38399c942d4a127aff5bb29333e9d4a5";

    struct StargateStorage {
        /// @notice The address of stargate contract
        address stargateRouter;
        address stargateRouterEth;
    }

    /// @notice Initialize the contract.
    /// @param addresses The new addresses of Stargate contracts
    function initStargate(StargateStorage calldata addresses) external {
        LibDiamond.enforceIsContractOwner();
        updateStargateAddressInternal(addresses.stargateRouter, addresses.stargateRouterEth);
    }

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable {}

    /// @notice A series of events with different status value to help us track the progress of cross-chain swap
    /// @param token The token address in the current network that is being bridged
    /// @param outputAmount The latest observed amount in the path, aka: input amount for source and output amount on dest
    /// @param status The latest status of the overall flow
    /// @param source The source address that initiated the transaction
    /// @param destination The destination address that received the money, ZERO address if not sent to the end-user yet
    event StargateSwapStatusUpdated(
        address token,
        uint256 outputAmount,
        LibInterchain.OperationStatus status,
        address source,
        address destination
    );

    /// @notice Emits when the cBridge address is updated
    /// @param _oldRouter The previous router address
    /// @param _oldRouterEth The previous routerEth address
    /// @param _newRouter The new router address
    /// @param _newRouterEth The new routerEth address
    event StargateAddressUpdated(address _oldRouter, address _oldRouterEth, address _newRouter, address _newRouterEth);

    /// @notice Updates the address of Stargate contract
    /// @param _router The new address of Stargate contract
    /// @param _routerEth The new address of Stargate contract
    function updateStargateAddress(address _router, address _routerEth) public {
        LibDiamond.enforceIsContractOwner();
        updateStargateAddressInternal(_router, _routerEth);
    }

    function stargateSwap(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoStargate.StargateRequest memory stargateRequest
    ) external payable nonReentrant {
        uint out;
        uint bridgeAmount;
        // if toToken is native coin and the user has not paid fee in msg.value,
        // then the user can pay bridge fee using output of swap.
        if (request.toToken == LibSwapper.ETH && msg.value == 0) {
            (out,) = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
            bridgeAmount = out - stargateRequest.stgFee;
        }
        else {
            (out,) = LibSwapper.onChainSwapsPreBridge(request, calls, stargateRequest.stgFee);
            bridgeAmount = out;
        }
        doStargateSwap(stargateRequest, request.toToken, bridgeAmount);
    }

    function stargateSwap(
        IRangoStargate.StargateRequest memory stargateRequest,
        address token,
        uint256 amount
    ) external payable nonReentrant {
        // transfer tokens if necessary
        if (token != LibSwapper.ETH) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
        } else {
            require(msg.value >= amount + stargateRequest.stgFee, "Insufficient ETH sent for bridging");
        }
        doStargateSwap(stargateRequest, token, amount);
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
        require(msg.sender == getStargateStorage().stargateRouter,
            "sgReceive function can only be called by Stargate router");
        Interchain.RangoInterChainMessage memory m = abi.decode((payload), (Interchain.RangoInterChainMessage));
        (address receivedToken, uint dstAmount, LibInterchain.OperationStatus status) = LibInterchain.handleDestinationMessage(_token, amountLD, m);

        emit StargateSwapStatusUpdated(receivedToken, dstAmount, status, m.originalSender, m.recipient);
    }

    /// @notice Executes a Stargate call
    /// @param request Required bridge params + interchain message that contains all the required info on the destination
    /// @param fromToken The address of source token to bridge
    /// @param inputAmount The amount to be bridged (excluding the fee)
    function doStargateSwap(
        StargateRequest memory request,
        address fromToken,
        uint256 inputAmount
    ) internal {
        StargateStorage storage s = getStargateStorage();

        address router = fromToken == LibSwapper.ETH ? s.stargateRouterEth : s.stargateRouter;
        require(router != LibSwapper.ETH, "Stargate router address not set");

        if (fromToken != LibSwapper.ETH) {
            LibSwapper.approve(fromToken, router, inputAmount);
        }

        bytes memory payload = request.bridgeType == StargateBridgeType.TRANSFER_WITH_MESSAGE
        ? abi.encode(request.payload)
        : new bytes(0);

        if (fromToken == LibSwapper.ETH) {
            if (request.payload.dstChainId > 0) {
                revert("Payload not supported on swapETH");
            }
            stargateRouterSwapEth(request, router, inputAmount);
        } else {
            stargateRouterSwap(request, router, inputAmount, request.stgFee, payload);
        }
    }

    function stargateRouterSwapEth(StargateRequest memory request, address router, uint256 bridgeAmount) private {
        IStargateRouter(router).swapETH{value : bridgeAmount + request.stgFee}(
            request.dstChainId,
            request.refundAddress,
            request.to,
            bridgeAmount,
            request.minAmountLD
        );
    }

    function stargateRouterSwap(
        StargateRequest memory request,
        address router,
        uint256 inputAmount,
        uint256 value,
        bytes memory payload
    ) private {
        IStargateRouter.lzTxObj memory lzTx = IStargateRouter.lzTxObj(
            request.dstGasForCall,
            request.dstNativeAmount,
            request.dstNativeAddr
        );
        IStargateRouter(router).swap{value : value}(
            request.dstChainId,
            request.srcPoolId,
            request.dstPoolId,
            request.refundAddress,
            inputAmount,
            request.minAmountLD,
            lzTx,
            request.to,
            payload
        );
    }

    function updateStargateAddressInternal(address _router, address _routerEth) private {
        StargateStorage storage s = getStargateStorage();
        address oldAddressRouter = s.stargateRouter;
        s.stargateRouter = _router;

        address oldAddressRouterEth = s.stargateRouterEth;
        s.stargateRouterEth = _routerEth;

        emit StargateAddressUpdated(oldAddressRouter, oldAddressRouterEth, _router, _routerEth);
    }

    /// @dev fetch local storage
    function getStargateStorage() private pure returns (StargateStorage storage s) {
        bytes32 namespace = STARGATE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
