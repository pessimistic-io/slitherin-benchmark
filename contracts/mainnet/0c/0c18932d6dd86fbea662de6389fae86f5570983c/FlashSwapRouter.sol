// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.6.10 <0.8.0;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IUniswapV2Router01.sol";

import "./ShareStaking.sol";

import "./ITranchessSwapCallee.sol";
import "./IPrimaryMarketV3.sol";
import "./ISwapRouter.sol";
import "./ITrancheIndexV2.sol";

/// @title Tranchess Flash Swap Router
/// @notice Router for stateless execution of flash swaps against Tranchess stable swaps
contract FlashSwapRouter is ITranchessSwapCallee, ITrancheIndexV2, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event SwapToggled(address externalRouter, bool enabled);
    event SwapRook(
        address indexed recipient,
        uint256 baseIn,
        uint256 quoteIn,
        uint256 baseOut,
        uint256 quoteOut
    );

    ISwapRouter public immutable tranchessRouter;
    mapping(address => bool) public externalRouterAllowlist;

    constructor(address tranchessRouter_) public {
        tranchessRouter = ISwapRouter(tranchessRouter_);
    }

    /// @dev Only meant for an off-chain client to call with eth_call.
    function getBuyR(
        IFundV3 fund,
        address queenSwapOrPrimaryMarketRouter,
        address tokenQuote,
        address externalRouter,
        address[] memory externalPath,
        uint256 outR
    ) external returns (uint256 quoteDelta, uint256 rookDelta) {
        uint256 underlyingAmount;
        uint256 totalQuoteAmount;
        {
            uint256 inQ = IPrimaryMarketV3(fund.primaryMarket()).getSplitForB(outR);
            underlyingAmount = IStableSwapCoreInternalRevertExpected(queenSwapOrPrimaryMarketRouter)
                .getQuoteIn(inQ);
            // Calculate the exact amount of quote asset to pay
            totalQuoteAmount = IUniswapV2Router01(externalRouter).getAmountsIn(
                underlyingAmount,
                externalPath
            )[0];
            // Calculate the amount of quote asset for selling BISHOP
            IStableSwap tranchessPair = tranchessRouter.getSwap(fund.tokenB(), tokenQuote);
            uint256 quoteAmount = tranchessPair.getQuoteOut(outR);
            // Calculate the user's portion of the payment to Tranchess swap
            quoteDelta = totalQuoteAmount.sub(quoteAmount);
            // Calculate the quote asset for underlying asset
            underlyingAmount = IUniswapV2Router01(externalRouter).getAmountsOut(
                totalQuoteAmount,
                externalPath
            )[externalPath.length - 1];
        }
        // Calculate creation of borrowed underlying for QUEEN
        uint256 outQ =
            IStableSwapCoreInternalRevertExpected(queenSwapOrPrimaryMarketRouter).getBaseOut(
                underlyingAmount
            );
        // Calculate the split result of QUEEN into BISHOP and ROOK
        rookDelta = IPrimaryMarketV3(fund.primaryMarket()).getSplit(outQ);
    }

    /// @dev Only meant for an off-chain client to call with eth_call.
    function getSellR(
        IFundV3 fund,
        address queenSwapOrPrimaryMarketRouter,
        address tokenQuote,
        address externalRouter,
        address[] memory externalPath,
        uint256 inR
    ) external returns (uint256 quoteDelta, uint256 rookDelta) {
        rookDelta = inR;
        uint256 quoteAmount =
            IStableSwap(tranchessRouter.getSwap(fund.tokenB(), tokenQuote)).getQuoteIn(inR);
        // Calculate merge result of BISHOP and ROOK into QUEEN
        (uint256 outQ, ) = IPrimaryMarketV3(fund.primaryMarket()).getMerge(inR);
        // Calculate the redemption from QUEEN to underlying
        uint256 underlyingAmount =
            IStableSwapCoreInternalRevertExpected(queenSwapOrPrimaryMarketRouter).getQuoteOut(outQ);
        // Calculate the underlying for quote asset
        uint256 totalQuoteAmount =
            IUniswapV2Router01(externalRouter).getAmountsOut(underlyingAmount, externalPath)[
                externalPath.length - 1
            ];
        // Calculate the rest of quote asset to user
        quoteDelta = totalQuoteAmount.sub(quoteAmount);
    }

    function toggleExternalRouter(address externalRouter) external onlyOwner {
        bool enabled = !externalRouterAllowlist[externalRouter];
        externalRouterAllowlist[externalRouter] = enabled;
        emit SwapToggled(externalRouter, enabled);
    }

    function buyR(
        IFundV3 fund,
        address queenSwapOrPrimaryMarketRouter,
        uint256 maxQuote,
        address recipient,
        address tokenQuote,
        address externalRouter,
        address[] memory externalPath,
        address staking,
        uint256 version,
        uint256 outR
    ) external {
        require(externalRouterAllowlist[externalRouter], "Invalid external router");
        uint256 underlyingAmount;
        uint256 totalQuoteAmount;
        bytes memory data;
        {
            uint256 inQ = IPrimaryMarketV3(fund.primaryMarket()).getSplitForB(outR);
            underlyingAmount = IStableSwapCoreInternalRevertExpected(queenSwapOrPrimaryMarketRouter)
                .getQuoteIn(inQ);
            // Calculate the exact amount of quote asset to pay
            totalQuoteAmount = IUniswapV2Router01(externalRouter).getAmountsIn(
                underlyingAmount,
                externalPath
            )[0];
            data = abi.encode(
                fund,
                queenSwapOrPrimaryMarketRouter,
                totalQuoteAmount,
                staking == address(0) ? recipient : staking,
                version,
                externalRouter,
                externalPath
            );
        }
        // Arrange the stable swap path
        IStableSwap tranchessPair = tranchessRouter.getSwap(fund.tokenB(), tokenQuote);
        address recipient_ = recipient;
        address tokenQuote_ = tokenQuote;
        // Calculate the amount of quote asset for selling BISHOP
        uint256 quoteAmount = tranchessPair.getQuoteOut(outR);
        // Send the user's portion of the payment to Tranchess swap
        uint256 resultAmount = totalQuoteAmount.sub(quoteAmount);
        require(resultAmount <= maxQuote, "Excessive input");
        IERC20(tokenQuote_).safeTransferFrom(msg.sender, address(this), resultAmount);
        tranchessPair.sell(version, quoteAmount, address(this), data);
        if (staking != address(0)) {
            ShareStaking(staking).deposit(TRANCHE_R, outR, recipient_, version);
        }
        emit SwapRook(recipient_, 0, resultAmount, outR, 0);
    }

    function sellR(
        IFundV3 fund,
        address queenSwapOrPrimaryMarketRouter,
        uint256 minQuote,
        address recipient,
        address tokenQuote,
        address externalRouter,
        address[] memory externalPath,
        uint256 version,
        uint256 inR
    ) external {
        require(externalRouterAllowlist[externalRouter], "Invalid external router");
        // Send the user's ROOK to this router
        fund.trancheTransferFrom(TRANCHE_R, msg.sender, address(this), inR, version);
        bytes memory data =
            abi.encode(
                fund,
                queenSwapOrPrimaryMarketRouter,
                minQuote,
                recipient,
                version,
                externalRouter,
                externalPath
            );
        tranchessRouter.getSwap(fund.tokenB(), tokenQuote).buy(version, inR, address(this), data);
    }

    function tranchessSwapCallback(
        uint256 baseOut,
        uint256 quoteOut,
        bytes calldata data
    ) external override {
        (
            IFundV3 fund,
            address queenSwapOrPrimaryMarketRouter,
            uint256 expectQuoteAmount,
            address recipient,
            uint256 version,
            ,

        ) = abi.decode(data, (IFundV3, address, uint256, address, uint256, address, address[]));
        address tokenQuote = IStableSwap(msg.sender).quoteAddress();
        require(
            msg.sender == address(tranchessRouter.getSwap(tokenQuote, fund.tokenB())),
            "Tranchess Pair check failed"
        );
        if (baseOut > 0) {
            uint256 resultAmount;
            {
                require(quoteOut == 0, "Unidirectional check failed");
                uint256 quoteAmount = IStableSwap(msg.sender).getQuoteIn(baseOut);
                // Merge BISHOP and ROOK into QUEEN
                uint256 outQ =
                    IPrimaryMarketV3(fund.primaryMarket()).merge(
                        queenSwapOrPrimaryMarketRouter,
                        baseOut,
                        version
                    );

                // Redeem or swap QUEEN for underlying
                uint256 underlyingAmount =
                    IStableSwapCoreInternalRevertExpected(queenSwapOrPrimaryMarketRouter)
                        .getQuoteOut(outQ);
                underlyingAmount = IStableSwapCoreInternalRevertExpected(
                    queenSwapOrPrimaryMarketRouter
                )
                    .sell(version, underlyingAmount, address(this), "");

                // Trade underlying for quote asset
                uint256 totalQuoteAmount =
                    _externalSwap(data, underlyingAmount, fund.tokenUnderlying(), tokenQuote);
                // Send back quote asset to tranchess swap
                IERC20(tokenQuote).safeTransfer(msg.sender, quoteAmount);
                // Send the rest of quote asset to user
                resultAmount = totalQuoteAmount.sub(quoteAmount);
                require(resultAmount >= expectQuoteAmount, "Insufficient output");
                IERC20(tokenQuote).safeTransfer(recipient, resultAmount);
            }
            emit SwapRook(recipient, baseOut, 0, 0, resultAmount);
        } else {
            address tokenUnderlying = fund.tokenUnderlying();
            // Trade quote asset for underlying asset
            uint256 underlyingAmount =
                _externalSwap(data, expectQuoteAmount, tokenQuote, tokenUnderlying);

            // Create or swap borrowed underlying for QUEEN
            uint256 outQ =
                IStableSwapCoreInternalRevertExpected(queenSwapOrPrimaryMarketRouter).getBaseOut(
                    underlyingAmount
                );
            IERC20(tokenUnderlying).safeTransfer(queenSwapOrPrimaryMarketRouter, underlyingAmount);
            outQ = IStableSwapCoreInternalRevertExpected(queenSwapOrPrimaryMarketRouter).buy(
                version,
                outQ,
                address(this),
                ""
            );

            // Split QUEEN into BISHOP and ROOK
            uint256 outB =
                IPrimaryMarketV3(fund.primaryMarket()).split(address(this), outQ, version);
            // Send back BISHOP to tranchess swap
            fund.trancheTransfer(TRANCHE_B, msg.sender, outB, version);
            // Send ROOK to user
            fund.trancheTransfer(TRANCHE_R, recipient, outB, version);
        }
    }

    function _externalSwap(
        bytes memory data,
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) private returns (uint256 amountOut) {
        (, , , , , address externalRouter, address[] memory externalPath) =
            abi.decode(data, (address, address, uint256, address, uint256, address, address[]));
        require(externalPath.length > 1, "Invalid external path");
        require(externalPath[0] == tokenIn, "Invalid token in");
        require(externalPath[externalPath.length - 1] == tokenOut, "Invalid token out");
        IERC20(tokenIn).safeApprove(externalRouter, amountIn);
        amountOut = IUniswapV2Router01(externalRouter).swapExactTokensForTokens(
            amountIn,
            0,
            externalPath,
            address(this),
            block.timestamp
        )[externalPath.length - 1];
    }
}

