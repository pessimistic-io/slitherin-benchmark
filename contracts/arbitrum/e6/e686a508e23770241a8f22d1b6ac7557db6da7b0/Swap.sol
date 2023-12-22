//SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.18;

import "./Ownable2StepUpgradeable.sol";
import "./UniswapV2Interface.sol";
import "./RouterConstants.sol";

contract Swap is RouterConstants, Ownable2StepUpgradeable {
    function swapThroughUniswap(
        address token0Address,
        address token1Address,
        uint256 amountIn,
        uint256 minAmountOut
    ) public returns (uint256) {
        uint24 poolFee = 3000;

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(token0Address, poolFee, token1Address),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });

        uint256 amountOut = UNI_ROUTER.exactInput(params);
        return amountOut;
    }

    //NOTE:Only involves swapping tokens for tokens, any operations involving ETH will be wrap/unwrap calls to WETH contract
    function swapThroughSushiswap(
        address token0Address,
        address token1Address,
        uint256 amountIn,
        uint256 minAmountOut
    ) public {
        address[] memory path = new address[](2);
        path[0] = token0Address;
        path[1] = token1Address;
        address to = address(this);
        uint256 deadline = block.timestamp;
        SUSHI_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, minAmountOut, path, to, deadline);
    }

    function swapThroughFraxswap(
        address token0Address,
        address token1Address,
        uint256 amountIn,
        uint256 minAmountOut
    ) public {
        address[] memory path = new address[](2);
        path[0] = token0Address;
        path[1] = token1Address;
        address to = address(this);
        uint256 deadline = block.timestamp;
        FRAX_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, minAmountOut, path, to, deadline);
    }

    //unwraps a position in plvGLP to native ETH, must be wrapped into WETH prior to repaying flash loan
    function unwindPlutusPosition() public {
        PLUTUS_DEPOSITOR.redeemAll();
        uint256 glpAmount = GLP.balanceOf(address(this));
        //TODO: update with a method to calculate minimum out given 2.5% slippage constraints.
        uint256 minOut = 0;
        GLP_ROUTER.unstakeAndRedeemGlp(address(WETH), glpAmount, minOut, address(this));
    }

    function plutusRedeem() public {
        PLUTUS_DEPOSITOR.redeemAll();
    }

    function glpRedeem() public {
        uint256 balance = GLP.balanceOf(address(this));
        GLP_ROUTER.unstakeAndRedeemGlp(address(WETH), balance, 0, address(this));
    }

    function wrapEther(uint256 amount) public returns (uint256) {
        (bool sent, ) = address(WETH).call{value: amount}("");
        require(sent, "Failed to send Ether");
        uint256 wethAmount = WETH.balanceOf(address(this));
        return wethAmount;
    }

    function unwrapEther(uint256 amountIn) public returns (uint256) {
        WETH.withdraw(amountIn);
        uint256 etherAmount = address(this).balance;
        return etherAmount;
    }

    function withdrawWETH() external onlyOwner {
        uint256 amount = WETH.balanceOf(address(this));
        require(WETH.transferFrom(address(this), msg.sender, amount), "Transfer must succeed");
    }

    function withdrawETH() external payable onlyOwner {
        uint256 balance = address(this).balance;
        (bool sent, ) = msg.sender.call{value: balance}("");
        require(sent, "Failed to send Ether");
    }

    function getMinimumSwapAmountOut(
        IERC20Extended tokenA,
        IERC20Extended tokenB,
        uint256 swapAmount,
        uint256 maxSlippage
    ) internal view returns (uint256) {
        AggregatorV3Interface tokenAAggregator = aggregators[address(tokenA)];
        AggregatorV3Interface tokenBAggregator = aggregators[address(tokenB)];
        uint8 tokenBDecimals = tokenB.decimals();
        uint256 tokenAPrice = getPriceFromChainlink(tokenAAggregator);
        uint256 tokenBPrice = getPriceFromChainlink(tokenBAggregator);
        uint256 conversionRatio = (tokenAPrice * BASE) / tokenBPrice;
        uint256 amountOutRaw = (swapAmount * conversionRatio) / BASE;
        uint256 decimalTruncation = 1 * 10 ** (18 - tokenBDecimals);
        uint256 slippageFactor = 1e18 - maxSlippage;
        return (amountOutRaw * slippageFactor) / (decimalTruncation * BASE);
    }

    /**
     * @notice Get price from ChainLink
     * @param aggregator The ChainLink aggregator to get the price of
     * @return The price
     */
    function getPriceFromChainlink(AggregatorV3Interface aggregator) internal view returns (uint256) {
        (uint80 roundId, int256 price, uint startedAt, uint updatedAt, uint80 answeredInRound) = aggregator
            .latestRoundData();
        require(roundId == answeredInRound && startedAt == updatedAt, "Price not fresh");
        require(price > 0, "invalid price");

        // Extend the decimals to 1e18.
        return uint256(price) * 10 ** (18 - uint256(aggregator.decimals()));
    }

    /**
     * @notice Get L2 sequencer status from Chainlink sequencer aggregator
     * @param sequencer the address of the Chainlink sequencer aggregator ("sequencerAddress" in constructor)
     * @return the L2 sequencer status as a boolean (true = the sequencer is up, false = the sequencer is down)
     */
    function getSequencerStatus(address sequencer) internal view returns (bool) {
        bool status;
        (, int256 answer, uint256 startedAt, , ) = AggregatorV3Interface(sequencer).latestRoundData();
        if (answer == 0 && block.timestamp - startedAt > GRACE_PERIOD_TIME) {
            status = true;
        } else if (answer == 1) {
            status = false;
        }
        return status;
    }

    event AggregatorUpdated(address indexed underlyingAddress, address indexed source);

    /**
     * @notice Set ChainLink aggregators for multiple underlying tokens
     * @param underlyingAddresses The list of underlying tokens
     * @param sources The list of ChainLink aggregator sources
     */
    function _setAggregators(address[] calldata underlyingAddresses, address[] calldata sources) external onlyOwner {
        require(underlyingAddresses.length == sources.length, "mismatched data");
        for (uint256 i = 0; i < underlyingAddresses.length; i++) {
            aggregators[underlyingAddresses[i]] = AggregatorV3Interface(sources[i]);
            emit AggregatorUpdated(underlyingAddresses[i], sources[i]);
        }
    }

    //function for wstETH swaps
    function swapThroughCurve(uint256 amountIn, uint256 minAmountOut, bool to) internal {
        address[9] memory route;
        uint256[3][4] memory swapParams;
        address[4] memory pools = [
            0x0000000000000000000000000000000000000000,
            0x0000000000000000000000000000000000000000,
            0x0000000000000000000000000000000000000000,
            0x0000000000000000000000000000000000000000
        ];

        if (to) {
            route = [
                0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
                0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80,
                0x5979D7b546E38E414F7E9822514be443A4800529,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000
            ];

            swapParams = [
                [uint256(0), uint256(0), uint256(15)],
                [uint256(0), uint256(1), uint256(1)],
                [uint256(0), uint256(0), uint256(0)],
                [uint256(0), uint256(0), uint256(0)]
            ];
        } else {
            route = [
                0x5979D7b546E38E414F7E9822514be443A4800529,
                0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80,
                0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
                0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000
            ];

            swapParams = [
                [uint256(1), uint256(0), uint256(1)],
                [uint256(0), uint256(0), uint256(15)],
                [uint256(0), uint256(0), uint256(0)],
                [uint256(0), uint256(0), uint256(0)]
            ];
        }

        CURVE_WSTETH_POOL.exchange_multiple(route, swapParams, amountIn, minAmountOut, pools);
    }
}

