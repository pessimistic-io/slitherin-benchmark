// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {IWeth} from "./IWeth.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IZapUniV2} from "./IZapUniV2.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {IRouter} from "./IRouter.sol";
import {ISwap} from "./ISwap.sol";
import {ILP} from "./ILP.sol";

/**
 * @title ZapUniV2
 * @author JonesDAO
 * @notice Go from whitelisted assets to LP tokens and deposit into our strategies.
 */
contract ZapUniV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable, IZapUniV2 {
    //////////////////////////////////////////////////////////
    //                  INTERNAL DATA STRUCTURES
    //////////////////////////////////////////////////////////

    struct Metavault {
        bool allowed;
        ILP pairAdapter;
        IRouter router;
        ISwap swapper;
        address token0;
        address token1;
    }

    //////////////////////////////////////////////////////////
    //                  CONSTANTS
    //////////////////////////////////////////////////////////

    // @notice Wrapped Ether inherits @erc20
    IWeth private constant WETH = IWeth(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    //////////////////////////////////////////////////////////
    //                  STORAGE
    //////////////////////////////////////////////////////////

    // @notice Store deployed metavaults information
    // @param LP address
    // @returns Metavault struct
    mapping(address => Metavault) private getMetavault;

    //////////////////////////////////////////////////////////
    //                  INIT
    //////////////////////////////////////////////////////////

    function initialize() external initializer {
        __Ownable_init();
    }

    //////////////////////////////////////////////////////////
    //                  ZAP!
    //////////////////////////////////////////////////////////

    /**
     * @notice Performs ZAP from asset to LP and deposits into the chosen Metavault.
     * @param pair Address of the liquidity pool for a given pair.
     * @param native Should be true if depositing native ETH
     * @param tokenIn Asset that will be zapped, can be any if `native` = true
     * @param amount Amount of assets that will be deposited
     * @return Amount of shares received
     */
    function zapIn(
        address pair,
        bool native,
        address tokenIn,
        uint256 amount,
        IRouter.OptionStrategy strategy,
        bool instant
    ) external payable nonReentrant returns (uint256) {
        // Checks if there is a Metavault for the given LP and returns it
        Metavault memory metavault = _getMetavault(pair);

        uint256 token0Amount;
        uint256 token1Amount;

        address token0 = metavault.token0;
        address token1 = metavault.token1;

        // If its not ETH nor WETH, convert half to WETH
        if (!native) {
            // Assert that tokenIn is part of the LP
            _verifyTokenIn(tokenIn, token0, token1);

            IERC20(tokenIn).transferFrom(msg.sender, address(this), amount);

            (token0Amount, token1Amount) = _zapIn(tokenIn, metavault, amount);
        } else {
            WETH.deposit{value: msg.value}();

            (token0Amount, token1Amount) = _zapIn(address(WETH), metavault, msg.value);
        }

        uint256 received = _addLiquidity(metavault.pairAdapter, token0, token1, token0Amount, token1Amount);

        IERC20(pair).approve(address(metavault.router), received);

        uint256 shares = metavault.router.deposit(received, strategy, instant, msg.sender);

        emit ZapIn(tokenIn, native, amount, strategy);

        return shares;
    }

    //////////////////////////////////////////////////////////
    //                  OWNER
    //////////////////////////////////////////////////////////

    function setMetavault(address pair, address router, address swapper, address pairAdapter) external onlyOwner {
        if (pair == address(0) || router == address(0) || swapper == address(0)) {
            revert();
        }

        IUniswapV2Pair pair_ = IUniswapV2Pair(pair);

        address token0 = pair_.token0();
        address token1 = pair_.token1();

        getMetavault[pair] = Metavault({
            router: IRouter(router),
            allowed: true,
            token0: token0,
            token1: token1,
            swapper: ISwap(swapper),
            pairAdapter: ILP(pairAdapter)
        });

        emit UpdateMetavault(pair, true);
    }

    function retireMetavault(address pair) external onlyOwner {
        getMetavault[pair].allowed = false;

        emit UpdateMetavault(pair, false);
    }

    function rescue(address tokenIn, uint256 amount, bool native) external onlyOwner {
        if (native) {
            (bool success,) = payable(msg.sender).call{value: amount}("");
            if (!success) {
                revert CallFailed();
            }
        } else {
            IERC20(tokenIn).transfer(msg.sender, amount);
        }

        emit Rescue(tokenIn, native, amount);
    }

    //////////////////////////////////////////////////////////
    //                  PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////

    function _zapIn(address tokenIn, Metavault memory metavault, uint256 amount)
        private
        returns (uint256 token0Amount, uint256 token1Amount)
    {
        if (tokenIn == metavault.token0) {
            token0Amount = amount / 2;
            token1Amount = _performSwap(metavault.swapper, tokenIn, metavault.token1, amount / 2);
        } else {
            token0Amount = _performSwap(metavault.swapper, tokenIn, metavault.token0, amount / 2);
            token1Amount = amount / 2;
        }
    }

    function _performSwap(ISwap swapper, address tokenIn, address tokenOut, uint256 amountIn)
        private
        returns (uint256)
    {
        // Build transaction
        // 0 slippage so uses swapper's default
        ISwap.SwapData memory swapData = ISwap.SwapData(tokenIn, tokenOut, amountIn, "");

        IERC20(tokenIn).approve(address(swapper), amountIn);

        uint256 received = swapper.swap(swapData);

        return received;
    }

    function _addLiquidity(ILP pairAdapter, address token0, address token1, uint256 amount0, uint256 amount1)
        private
        returns (uint256)
    {
        IERC20(token0).approve(address(pairAdapter), amount0);
        IERC20(token1).approve(address(pairAdapter), amount1);

        uint256 received = pairAdapter.buildWithBothTokens(token0, token1, amount0, amount1);

        return received;
    }

    function _verifyTokenIn(address tokenIn, address token0, address token1) private pure {
        if (tokenIn != token0 && tokenIn != token1) {
            revert NotPartOfTheLp(tokenIn);
        }
    }

    function _getMetavault(address pair) private view returns (Metavault memory) {
        Metavault memory metavault = getMetavault[pair];

        if (metavault.allowed) {
            return metavault;
        }

        revert NoMetavault(pair);
    }

    //////////////////////////////////////////////////////////
    //                  ERRORS
    //////////////////////////////////////////////////////////

    error NoMetavault(address pair);
    error NotPartOfTheLp(address token);
    error CallFailed();

    //////////////////////////////////////////////////////////
    //                  EVENTS
    //////////////////////////////////////////////////////////

    event Rescue(address tokenOut, bool native, uint256 amount);
    event UpdateMetavault(address indexed pair, bool indexed allowed);
    event ZapIn(address tokenIn, bool native, uint256 amount, IRouter.OptionStrategy indexed strategy);

    receive() external payable {}
}

