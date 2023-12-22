/**
 * LP Adapter for UniV2
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./clients_UniV2.sol";
import "./LpAdapter.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import "./Univ2Lib.sol";
import "./IUniv2Router.sol";
import "./IVault.sol";
import "./IUniV2Factory.sol";

contract UniV2LpAdapterFacet {
    // Libs
    using SafeERC20 for IERC20;
    using UniswapV2Library for *;

    /**
     * Add Liquidity To A Uniswap V2 LPClient
     * @param client - LP Adapter compliant LPClient struct
     * @param tokenA - token #1
     * @param tokenB - token #2
     * @param amountA - amount for token #1
     * @param amountB - amount for token #2
     * @notice Does not receive any extra data or arguments.
     */
    function addLiquidityUniV2(
        LPClient calldata client,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external payable {
        IUniswapV2Router router = IUniswapV2Router(client.clientAddress);

        address factory = router.factory();

        // Sort tokens & amounts
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
            (amountA, amountB) = (amountB, amountA);
        }

        (amountA, amountB) = _determineAddAmounts(
            factory,
            tokenA,
            tokenB,
            amountA,
            amountB
        );

        // Handle a native token transfer
        bool includesNativeToken = tokenA == address(0) || tokenB == address(0);
        if (includesNativeToken) {
            (address token, uint256 ethAmount, uint256 tokenAmount) = tokenA ==
                address(0)
                ? (tokenB, amountB, amountA)
                : (tokenA, amountA, amountB);

            require(
                msg.value >= ethAmount,
                "Insufficinet msg.value for native ETH liq op"
            );

            if (
                IERC20(token).allowance(msg.sender, address(this)) < tokenAmount
            ) IVault(msg.sender).approveDaddyDiamond(token, type(uint256).max);

            IERC20(token).safeTransferFrom(
                msg.sender,
                address(this),
                tokenAmount
            );

            if (msg.value > ethAmount)
                payable(msg.sender).transfer(msg.value - ethAmount);

            IUniswapV2Router(client.clientAddress).addLiquidityETH(
                token,
                tokenAmount,
                0,
                0,
                msg.sender,
                type(uint256).max
            );

            return;
        }

        // Approve ourselves from within the vault
        if (IERC20(tokenA).allowance(msg.sender, address(this)) < amountA)
            IVault(msg.sender).approveDaddyDiamond(tokenA, type(uint256).max);
        if (IERC20(tokenB).allowance(msg.sender, address(this)) < amountB)
            IVault(msg.sender).approveDaddyDiamond(tokenB, type(uint256).max);

        // Get the tokens
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

        // Approve the client address
        if (
            IERC20(tokenA).allowance(address(this), client.clientAddress) <
            amountA
        ) IERC20(tokenA).approve(client.clientAddress, type(uint256).max);
        if (
            IERC20(tokenB).allowance(address(this), client.clientAddress) <
            amountB
        ) IERC20(tokenB).approve(client.clientAddress, type(uint256).max);

        IUniswapV2Router(client.clientAddress).addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            0,
            0,
            msg.sender,
            type(uint256).max
        );
    }

    /**
     * Internal function to get the amounts to add
     * @param factory - The address of the factory (to get reserves)
     * @param tokenA - Sorted token #1
     * @param tokenB - Sorted token #2
     * @param amountA - Sorted amount #1
     * @param amountB - Sorted amount #2
     */
    function _determineAddAmounts(
        address factory,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal view returns (uint256 desiredAmountA, uint256 desiredAmountB) {
        (uint256 reserveA, uint256 reserveB) = factory.getReserves(
            tokenA,
            tokenB
        );

        if (reserveA == 0 && reserveB == 0) return (amountA, amountB);

        uint256 requiredAmountBForAmountA = amountA.quote(reserveA, reserveB);

        uint256 requiredAmountAForAmountB = amountB.quote(reserveB, reserveA);

        (desiredAmountA, desiredAmountB) = requiredAmountBForAmountA > amountB
            ? (requiredAmountAForAmountB, amountB)
            : (amountA, requiredAmountBForAmountA);
    }

    /**
     * Remove liquidity
     * @param client - LP Adapter compliant LPClient struct
     * @param tokenA - token #1
     * @param tokenB - token #2
     * @param lpAmount - Amount of LP tokens to remove
     */
    function removeLiquidityUniV2(
        LPClient calldata client,
        address tokenA,
        address tokenB,
        uint256 lpAmount
    ) external {
        IUniswapV2Router router = IUniswapV2Router(client.clientAddress);

        address factory = router.factory();

        IERC20 pair = IERC20(
            IUniswapV2Factory(factory).getPair(tokenA, tokenB)
        );

        if (IERC20(pair).allowance(msg.sender, address(this)) < lpAmount)
            IVault(msg.sender).approveDaddyDiamond(
                address(pair),
                type(uint256).max
            );

        pair.safeTransferFrom(msg.sender, address(this), lpAmount);

        // Approve client for LP token (transferFrom from us)
        if (
            IERC20(pair).allowance(address(this), client.clientAddress) <
            lpAmount
        ) IERC20(pair).approve(client.clientAddress, type(uint256).max);

        bool includesNativeToken = tokenA == address(0) || tokenB == address(0);

        if (includesNativeToken) {
            address token = tokenA == address(0) ? tokenB : tokenA;

            router.removeLiquidityETH(
                token,
                lpAmount,
                0,
                0,
                msg.sender,
                type(uint256).max
            );

            return;
        }

        router.removeLiquidity(
            tokenA,
            tokenB,
            lpAmount,
            0,
            0,
            msg.sender,
            type(uint256).max
        );
    }

    // ==================
    //     GETTERS
    // ==================
    /**
     * Get an address' balance of an LP pair token
     * @param client The LP client to check on
     * @param tokenA First token of the pair (unsorted)
     * @param tokenB Second token of the pair(unsorted)
     * @param owner owner to check the balance of
     * @return ownerLpBalance
     */
    function balanceOfUniV2LP(
        LPClient calldata client,
        address tokenA,
        address tokenB,
        address owner
    ) external view returns (uint256 ownerLpBalance) {
        address factory = client.clientAddress;
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        ownerLpBalance = IERC20(pair).balanceOf(owner);
    }
}

