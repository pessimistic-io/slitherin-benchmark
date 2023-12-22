// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

// Storage imports
import { LibStorage, BattleflyGameStorage } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

//interfaces
import { IERC20 } from "./IERC20.sol";
import "./SafeERC20.sol";
import "./AggregatorV2V3Interface.sol";
import { IUniswapV2Router02 } from "./IUniswapV2Router02.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { IQuoter } from "./IQuoter.sol";
import { IGameV2 } from "./IGameV2.sol";
import "./SafeCast.sol";

library LibPaymentUtils {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;

    event PaymentMade(
        address account,
        uint256 currency,
        uint256 productType,
        uint256 pricePerProductTypeInMagic,
        uint256 productTypeAmount
    );

    event USDCPaymentMade(
        address account,
        uint256 currency,
        uint256 productType,
        uint256 pricePerProductTypeInUSDC,
        uint256 productTypeAmount
    );

    event MagicTransferredToGameContract(
        address account,
        uint256 magicAmount,
        uint256 treasuryEthAmount,
        uint256 treasuryMagicAmount,
        uint256 treasuryUsdcAmount,
        uint256 treasuryUsdcOriginalAmount,
        uint256 treasuryArbAmount
    );

    function gs() internal pure returns (BattleflyGameStorage storage) {
        return LibStorage.gameStorage();
    }

    function pay(
        uint256 currency,
        uint256 productType,
        uint256 pricePerProductTypeInMagic,
        uint256 productTypeAmount,
        uint256 ethValue
    ) internal {
        // Currencies: 0 = ETH, 1 = Magic, 2 = USDCe, 3 = USDC Original (circle), 4 = ARB
        if (currency >= 5) revert Errors.InvalidCurrency();
        uint256 expectedAmount = pricePerProductTypeInMagic * productTypeAmount;
        if (expectedAmount > 0) {
            uint256 amountRequired = getAmountOfCurrencyForXMagic(currency, expectedAmount);
            if (currency == 0) {
                if (ethValue < amountRequired) {
                    revert Errors.InsufficientAmount();
                } else {
                    (bool sent, ) = payable(msg.sender).call{ value: ethValue - amountRequired }("");
                    if (!sent) revert Errors.EthTransferFailed();
                    gs().ethReserve += amountRequired;
                }
            } else if (currency == 1) {
                IERC20(gs().magic).transferFrom(msg.sender, address(this), amountRequired);
                gs().magicReserve += amountRequired;
            } else if (currency == 2) {
                IERC20(gs().usdc).transferFrom(msg.sender, address(this), amountRequired);
                gs().usdcReserve += amountRequired;
            } else if(currency == 3) {
                IERC20(gs().usdcOriginal).transferFrom(msg.sender, address(this), amountRequired);
                gs().usdcOriginalReserve += amountRequired;
            } else {
                IERC20(gs().arb).transferFrom(msg.sender, address(this), amountRequired);
                gs().arbReserve += amountRequired;
            }
            emit PaymentMade(msg.sender, currency, productType, pricePerProductTypeInMagic, productTypeAmount);
        } else {
            revert Errors.InsufficientAmount();
        }
    }

    function payUSDC(
        uint256 currency,
        uint256 productType,
        uint256 pricePerProductTypeInUSDC,
        uint256 productTypeAmount,
        uint256 ethValue
    ) internal {
        // Currencies: 0 = ETH, 1 = Magic, 2 = USDCe, 3 = USDC Original (circle), 4 = ARB
        if (currency >= 5) revert Errors.InvalidCurrency();
        uint256 expectedAmount = pricePerProductTypeInUSDC * productTypeAmount;
        if (expectedAmount > 0) {
            uint256 amountRequired = getAmountOfCurrencyForXUSDC(currency, expectedAmount);
            if (currency == 0) {
                if (ethValue < amountRequired) {
                    revert Errors.InsufficientAmount();
                } else {
                    (bool sent, ) = payable(msg.sender).call{ value: ethValue - amountRequired }("");
                    if (!sent) revert Errors.EthTransferFailed();
                    gs().ethReserve += amountRequired;
                }
            } else if (currency == 1) {
                IERC20(gs().magic).transferFrom(msg.sender, address(this), amountRequired);
                gs().magicReserve += amountRequired;
            } else if (currency == 2) {
                IERC20(gs().usdc).transferFrom(msg.sender, address(this), amountRequired);
                gs().usdcReserve += amountRequired;
            } else if(currency == 3) {
                IERC20(gs().usdcOriginal).transferFrom(msg.sender, address(this), amountRequired);
                gs().usdcOriginalReserve += amountRequired;
            } else {
                IERC20(gs().arb).transferFrom(msg.sender, address(this), amountRequired);
                gs().arbReserve += amountRequired;
            }
            emit USDCPaymentMade(msg.sender, currency, productType, pricePerProductTypeInUSDC, productTypeAmount);
        } else {
            revert Errors.InsufficientAmount();
        }
    }

    function getPaymentReceiver() internal view returns (address) {
        return gs().paymentReceiver;
    }

    function getUSDC() internal view returns (address) {
        return gs().usdc;
    }

    function getUSDCOriginal() internal view returns (address) {
        return gs().usdcOriginal;
    }

    function getArb() internal view returns (address) {
        return gs().arb;
    }

    function getWETH() internal view returns (address) {
        return gs().weth;
    }

    function getUSDCDataFeed() internal view returns (AggregatorV2V3Interface) {
        return AggregatorV2V3Interface(gs().usdcDataFeedAddress);
    }

    function getETHDataFeed() internal view returns (AggregatorV2V3Interface) {
        return AggregatorV2V3Interface(gs().ethDataFeedAddress);
    }

    function getMagicDataFeed() internal view returns (AggregatorV2V3Interface) {
        return AggregatorV2V3Interface(gs().magicDataFeedAddress);
    }

    function getArbDataFeed() internal view returns (AggregatorV2V3Interface) {
        return AggregatorV2V3Interface(gs().arbDataFeedAddress);
    }

    function getSequencerUptimeFeed() internal view returns (AggregatorV2V3Interface) {
        return AggregatorV2V3Interface(gs().sequencerUptimeFeedAddress);
    }

    function getAmountOfCurrencyForXMagic(uint256 currency, uint256 magicAmount) internal view returns (uint256) {
        if (currency >= 5) revert Errors.InvalidCurrency();
        uint256 amount = 0;
        if (currency == 1) {
            amount = magicAmount;
            return amount;
        }

        //Check Sequencer status
        (, int256 answer, uint256 startedAt, , ) = getSequencerUptimeFeed().latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert Errors.SequencerDown();
        }

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= gs().sequencerGracePeriod) {
            revert Errors.GracePeriodNotOver();
        }

        if (currency == 0) {
            (, int answerETH, , , ) = getETHDataFeed().latestRoundData();
            (, int answerMagic, , , ) = getMagicDataFeed().latestRoundData();
            amount = (((answerMagic.toUint256() * 10 ** 18) / answerETH.toUint256()) * magicAmount) / 10 ** 18;
        }
        if (currency == 2 || currency == 3) {
            (, int answerUSDC, , , ) = getUSDCDataFeed().latestRoundData();
            (, int answerMagic, , , ) = getMagicDataFeed().latestRoundData();
            amount = (((answerMagic.toUint256() * 10 ** 18) / answerUSDC.toUint256()) * magicAmount) / 10 ** 30;
        }
        if (currency == 4) {
            (, int answerArb, , , ) = getArbDataFeed().latestRoundData();
            (, int answerMagic, , , ) = getMagicDataFeed().latestRoundData();
            amount = (((answerMagic.toUint256() * 10 ** 18) / answerArb.toUint256()) * magicAmount) / 10 ** 18;
        }
        return amount;
    }

    function getAmountOfCurrencyForXUSDC(uint256 currency, uint256 usdcAmount) internal view returns (uint256) {
        if (currency >= 5) revert Errors.InvalidCurrency();
        uint256 amount = 0;
        if (currency == 2 || currency == 3) {
            amount = usdcAmount;
            return amount;
        }

        //Check Sequencer status
        (, int256 answer, uint256 startedAt, , ) = getSequencerUptimeFeed().latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert Errors.SequencerDown();
        }

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= gs().sequencerGracePeriod) {
            revert Errors.GracePeriodNotOver();
        }

        if (currency == 0) {
            (, int answerETH, , , ) = getETHDataFeed().latestRoundData();
            (, int answerUSDC, , , ) = getUSDCDataFeed().latestRoundData();
            amount = (((answerUSDC.toUint256() * 10 ** 18) / answerETH.toUint256()) * usdcAmount) / 10 ** 6;
        }
        if (currency == 1) {
            (, int answerMagic, , , ) = getMagicDataFeed().latestRoundData();
            (, int answerUSDC, , , ) = getUSDCDataFeed().latestRoundData();
            amount = (((answerUSDC.toUint256() * 10 ** 18) / answerMagic.toUint256()) * usdcAmount) / 10 ** 6;
        }
        if (currency == 4) {
            (, int answerArb, , , ) = getArbDataFeed().latestRoundData();
            (, int answerUSDC, , , ) = getUSDCDataFeed().latestRoundData();
            amount = (((answerUSDC.toUint256() * 10 ** 18) / answerArb.toUint256()) * usdcAmount) / 10 ** 6;
        }
        return amount;
    }

    function transferMagicToGameContract() internal {
        uint256 treshold = IGameV2(gs().gameV2).coldStorageTreshold();
        uint256 balance = IERC20(gs().magic).balanceOf(gs().gameV2);
        uint256 topupAmount = 0;
        if (balance < treshold) {
            topupAmount = processMagicForWithdrawal(balance, treshold, 0);
            if (topupAmount > 0) {
                IERC20(gs().magic).transfer(gs().gameV2, topupAmount);
            }
            gs().magicReserve -= topupAmount;
        }
        //Transfer remainders to payment receiver
        if (gs().magicReserve > 0) {
            IERC20(gs().magic).transfer(gs().paymentReceiver, gs().magicReserve);
        }
        if (gs().usdcReserve > 0) {
            IERC20(gs().usdc).transfer(gs().paymentReceiver, gs().usdcReserve);
        }
        if (gs().usdcOriginalReserve > 0) {
            IERC20(gs().usdcOriginal).transfer(gs().paymentReceiver, gs().usdcOriginalReserve);
        }
        if (gs().arbReserve > 0) {
            IERC20(gs().arb).transfer(gs().paymentReceiver, gs().arbReserve);
        }
        if (gs().ethReserve > 0) {
            (bool sent, ) = payable(gs().paymentReceiver).call{ value: gs().ethReserve }("");
            if (!sent) revert Errors.EthTransferFailed();
        }
        emit MagicTransferredToGameContract(
            msg.sender,
            topupAmount,
            gs().ethReserve,
            gs().magicReserve,
            gs().usdcReserve,
            gs().usdcOriginalReserve,
            gs().arbReserve
        );
        gs().magicReserve = 0;
        gs().usdcReserve = 0;
        gs().usdcOriginalReserve = 0;
        gs().ethReserve = 0;
        gs().arbReserve = 0;
    }

    function processMagicForWithdrawal(
        uint256 balance,
        uint256 treshold,
        uint256 topupAmount
    ) internal returns (uint256) {
        uint256 transferAmount = 0;
        if (balance + gs().magicReserve > treshold) {
            transferAmount = balance + gs().magicReserve - treshold;
            topupAmount += transferAmount;
        } else {
            transferAmount = gs().magicReserve;
            topupAmount += gs().magicReserve;
        }
        balance += topupAmount;
        if (balance < treshold) {
            topupAmount = processEthForWithdrawal(balance, treshold, topupAmount);
        }
        return topupAmount;
    }

    function processEthForWithdrawal(
        uint256 balance,
        uint256 treshold,
        uint256 topupAmount
    ) internal returns (uint256) {
        uint256 transferAmount = 0;
        uint256 fillable = treshold - balance;
        address[] memory path = new address[](2);
        path[0] = gs().weth;
        path[1] = gs().magic;
        uint256 expectedEth = IUniswapV2Router02(gs().sushiswapRouter).getAmountsIn(fillable, path)[0];
        expectedEth = (expectedEth * (gs().bpsDenominator + gs().slippageInBPS)) / gs().bpsDenominator;
        if (expectedEth <= gs().ethReserve && gs().ethReserve > 0) {
            gs().ethReserve -= IUniswapV2Router02(gs().sushiswapRouter).swapETHForExactTokens{ value: expectedEth }(
                fillable,
                path,
                address(this),
                block.timestamp
            )[0];
            gs().magicReserve += fillable;
            balance += fillable;
            topupAmount += fillable;
        } else {
            if (gs().ethReserve > 0) {
                uint256 expectedMagic = IUniswapV2Router02(gs().sushiswapRouter).getAmountsOut(gs().ethReserve, path)[
                    0
                ];
                expectedMagic = (expectedMagic * (gs().bpsDenominator + gs().slippageInBPS)) / gs().bpsDenominator;
                transferAmount += IUniswapV2Router02(gs().sushiswapRouter).swapExactETHForTokens{
                    value: gs().ethReserve
                }(expectedMagic, path, address(this), block.timestamp)[1];
                gs().ethReserve = 0;
                gs().magicReserve += transferAmount;
                balance += transferAmount;
                topupAmount += transferAmount;
            }
            if (balance < treshold) {
                topupAmount = processUsdcForWithdrawal(balance, treshold, topupAmount);
            }
        }
        return topupAmount;
    }

    function processUsdcForWithdrawal(
        uint256 balance,
        uint256 treshold,
        uint256 topupAmount
    ) internal returns (uint256) {
        swapUSDCOriginalToUSDC();
        uint256 transferAmount = 0;
        uint256 fillable = treshold - balance;
        address[] memory path = new address[](3);
        path[0] = gs().usdc;
        path[1] = gs().weth;
        path[2] = gs().magic;
        uint256 expectedUsdc = IUniswapV2Router02(gs().sushiswapRouter).getAmountsIn(fillable, path)[0];
        expectedUsdc = (expectedUsdc * (gs().bpsDenominator + gs().slippageInBPS)) / gs().bpsDenominator;
        if (expectedUsdc <= gs().usdcReserve && gs().usdcReserve > 0) {
            IERC20(gs().usdc).approve(gs().sushiswapRouter, expectedUsdc);
            gs().usdcReserve -= IUniswapV2Router02(gs().sushiswapRouter).swapTokensForExactTokens(
                fillable,
                expectedUsdc,
                path,
                address(this),
                block.timestamp
            )[0];
            gs().magicReserve += fillable;
            topupAmount += fillable;
        } else {
            if (gs().usdcReserve > 0) {
                uint256 expectedMagic = IUniswapV2Router02(gs().sushiswapRouter).getAmountsOut(gs().usdcReserve, path)[
                    1
                ];
                expectedMagic = (expectedMagic * (gs().bpsDenominator - gs().slippageInBPS)) / gs().bpsDenominator;
                IERC20(gs().usdc).approve(gs().sushiswapRouter, gs().usdcReserve);
                transferAmount += IUniswapV2Router02(gs().sushiswapRouter).swapExactTokensForTokens(
                    gs().usdcReserve,
                    expectedMagic,
                    path,
                    address(this),
                    block.timestamp
                )[2];
                gs().usdcReserve = 0;
                gs().magicReserve += transferAmount;
                balance += transferAmount;
                topupAmount += transferAmount;
            }
            if (balance < treshold) {
                topupAmount = processArbForWithdrawal(balance, treshold, topupAmount);
            }
        }
        return topupAmount;
    }

    function processArbForWithdrawal(
        uint256 balance,
        uint256 treshold,
        uint256 topupAmount
    ) internal returns (uint256) {
        uint256 transferAmount = 0;
        uint256 fillable = treshold - balance;
        address[] memory path = new address[](3);
        path[0] = gs().arb;
        path[1] = gs().weth;
        path[2] = gs().magic;
        uint256 expectedArb = IUniswapV2Router02(gs().sushiswapRouter).getAmountsIn(fillable, path)[0];
        expectedArb = (expectedArb * (gs().bpsDenominator + gs().slippageInBPS)) / gs().bpsDenominator;
        if (expectedArb <= gs().arbReserve && gs().arbReserve > 0) {
            IERC20(gs().arb).approve(gs().sushiswapRouter, expectedArb);
            gs().arbReserve -= IUniswapV2Router02(gs().sushiswapRouter).swapTokensForExactTokens(
                fillable,
                expectedArb,
                path,
                address(this),
                block.timestamp
            )[0];
            gs().magicReserve += fillable;
            topupAmount += fillable;
        } else {
            if (gs().arbReserve > 0) {
                uint256 expectedMagic = IUniswapV2Router02(gs().sushiswapRouter).getAmountsOut(gs().arbReserve, path)[
                1
                ];
                expectedMagic = (expectedMagic * (gs().bpsDenominator - gs().slippageInBPS)) / gs().bpsDenominator;
                IERC20(gs().arb).approve(gs().sushiswapRouter, gs().arbReserve);
                transferAmount += IUniswapV2Router02(gs().sushiswapRouter).swapExactTokensForTokens(
                    gs().arbReserve,
                    expectedMagic,
                    path,
                    address(this),
                    block.timestamp
                )[2];
                gs().arbReserve = 0;
                gs().magicReserve += transferAmount;
                topupAmount += transferAmount;
            }
        }
        return topupAmount;
    }

    function swapUSDCOriginalToUSDC() internal {
        if (gs().usdcOriginalReserve > 0) {
            uint256 amountOutMin = IQuoter(gs().uniswapV3Quoter).quoteExactOutputSingle(
                gs().usdcOriginal,
                gs().usdc,
                gs().usdcToUsdcOriginalPoolFee,
                gs().usdcOriginalReserve,
                0
            );
            amountOutMin = (amountOutMin * (gs().bpsDenominator - gs().slippageInBPS)) / gs().bpsDenominator;

            IERC20(gs().usdcOriginal).approve(gs().uniswapV3Router, gs().usdcOriginalReserve);

            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: gs().usdcOriginal,
                tokenOut: gs().usdc,
                fee: gs().usdcToUsdcOriginalPoolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: gs().usdcOriginalReserve,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            });

            uint256 amountOut = ISwapRouter(gs().uniswapV3Router).exactInputSingle(params);
            gs().usdcReserve += amountOut;
            gs().usdcOriginalReserve = 0;
        }
    }

    function getMagicReserve() internal view returns (uint256) {
        return gs().magicReserve;
    }

    function getEthReserve() internal view returns (uint256) {
        return gs().ethReserve;
    }

    function getUsdcReserve() internal view returns (uint256) {
        return gs().usdcReserve;
    }

    function getUsdcOriginalReserve() internal view returns (uint256) {
        return gs().usdcOriginalReserve;
    }

    function getArbReserve() internal view returns (uint256) {
        return gs().arbReserve;
    }

    function getUSDCDataFeedAddress() internal view returns (address) {
        return gs().usdcDataFeedAddress;
    }

    function getArbDataFeedAddress() internal view returns (address) {
        return gs().arbDataFeedAddress;
    }

    function getEthDataFeedAddress() internal view returns (address) {
        return gs().ethDataFeedAddress;
    }

    function getMagicDataFeedAddress() internal view returns (address) {
        return gs().magicDataFeedAddress;
    }

    function getSushiswapRouter() internal view returns (address) {
        return gs().sushiswapRouter;
    }

    function getUniswapV3Router() internal view returns (address) {
        return gs().uniswapV3Router;
    }

    function getUniswapV3Quoter() internal view returns (address) {
        return gs().uniswapV3Quoter;
    }

    function getUsdcToUsdcOriginalPoolFee() internal view returns (uint24) {
        return gs().usdcToUsdcOriginalPoolFee;
    }

    function getSequencerUptimeFeedAddress() internal view returns (address) {
        return gs().sequencerUptimeFeedAddress;
    }

    function getSequencerGracePeriod() internal view returns (uint256) {
        return gs().sequencerGracePeriod;
    }
}

