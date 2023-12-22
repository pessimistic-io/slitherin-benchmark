/// Copyright (C) 2022 Portals.fi

/// @author Portals.fi
/// @notice This contract removes liquidity from Uniswap V2-like pools into any ERC20 token or the network token.

/// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.11;

import "./PortalBaseV1.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router.sol";
import "./IUniswapV2Pair.sol";
import "./IPortalRegistry.sol";

contract UniswapV2PortalOut is PortalBaseV1 {
    using SafeTransferLib for address;
    using SafeTransferLib for ERC20;

    uint256 internal constant DEADLINE = type(uint256).max;

    /// @notice Emitted when a portal is exited
    /// @param sellToken The ERC20 token address to spend (address(0) if network token)
    /// @param sellAmount The quantity of sellToken to Portal out
    /// @param buyToken The ERC20 token address to buy (address(0) if network token)
    /// @param buyAmount The quantity of buyToken received
    /// @param fee The fee in BPS
    /// @param sender The  msg.sender
    /// @param partner The front end operator address
    event PortalOut(
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 buyAmount,
        uint256 fee,
        address indexed sender,
        address indexed partner
    );

    /// Thrown when insufficient liquidity is received after withdrawal
    /// @param buyAmount The amount of liquidity received
    /// @param minBuyAmount The minimum acceptable quantity of liquidity received
    error InsufficientBuy(uint256 buyAmount, uint256 minBuyAmount);

    constructor(
        bytes32 protocolId,
        PortalType portalType,
        IPortalRegistry registry,
        address exchange,
        address wrappedNetworkToken,
        uint256 fee
    )
        PortalBaseV1(
            protocolId,
            portalType,
            registry,
            exchange,
            wrappedNetworkToken,
            fee
        )
    {}

    /// @notice Remove liquidity from Uniswap V2-like pools into network tokens/ERC20 tokens
    /// @param sellToken The pool (i.e. pair) address
    /// @param sellAmount The quantity of sellToken to Portal out
    /// @param buyToken The ERC20 token address to buy (address(0) if network token)
    /// @param minBuyAmount The minimum quantity of buyTokens to receive. Reverts otherwise
    /// @param target The excecution target for the swaps
    /// @param data  The encoded calls for the buyToken swaps
    /// @param partner The front end operator address
    /// @return buyAmount The quantity of buyToken acquired
    function portalOut(
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 minBuyAmount,
        address target,
        bytes[] calldata data,
        address partner,
        IUniswapV2Router02 router
    ) external pausable returns (uint256 buyAmount) {
        sellAmount = _transferFromCaller(sellToken, sellAmount);

        buyAmount = _remove(
            router,
            sellToken,
            sellAmount,
            buyToken,
            target,
            data
        );

        buyAmount = _getFeeAmount(buyAmount, fee);

        if (buyAmount < minBuyAmount)
            revert InsufficientBuy(buyAmount, minBuyAmount);

        buyToken == address(0)
            ? msg.sender.safeTransferETH(buyAmount)
            : ERC20(buyToken).safeTransfer(msg.sender, buyAmount);

        emit PortalOut(
            sellToken,
            sellAmount,
            buyToken,
            buyAmount,
            fee,
            msg.sender,
            partner
        );
    }

    /// @notice Removes both tokens from the pool and swaps for buyToken
    /// @param router The router belonging to the protocol to remove liquidity from
    /// @param sellToken The pair address (i.e. the LP address)
    /// @param buyToken The ERC20 token address to buy (address(0) if network token)
    /// @param sellAmount The quantity of LP tokens to remove from the pool
    /// @param target The excecution target for the swaps
    /// @param data  The encoded calls for the buyToken swaps
    /// @return buyAmount The quantity of buyToken acquired
    function _remove(
        IUniswapV2Router02 router,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        address target,
        bytes[] calldata data
    ) internal returns (uint256 buyAmount) {
        IUniswapV2Pair pair = IUniswapV2Pair(sellToken);

        _approve(sellToken, address(router), sellAmount);

        address token0 = pair.token0();
        address token1 = pair.token1();

        (uint256 amount0, uint256 amount1) = router.removeLiquidity(
            token0,
            token1,
            sellAmount,
            1,
            1,
            address(this),
            DEADLINE
        );

        buyAmount = _execute(token0, amount0, buyToken, target, data[0]);
        buyAmount += _execute(token1, amount1, buyToken, target, data[1]);
    }
}

