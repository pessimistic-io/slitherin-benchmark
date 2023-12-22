// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

// Storage imports
import { LibStorage, BattleflyGameStorage, PaymentType } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

//interfaces
import { IERC20 } from "./IERC20.sol";
import { IERC1155 } from "./IERC1155.sol";
import { IUniswapV2Router02 } from "./IUniswapV2Router02.sol";
import { IUniswapV2Pair } from "./IUniswapV2Pair.sol";

library LibCreditUtils {
    event LiquidityAdded(uint256 liquidity, uint256 providedMagic, uint256 providedGFly);

    function gs() internal pure returns (BattleflyGameStorage storage) {
        return LibStorage.gameStorage();
    }

    // create credits
    function createCredit(
        uint256 creditType,
        uint256 amount,
        PaymentType paymentType,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) internal {
        if (amount < 1) revert Errors.InvalidAmount();
        if (!gs().creditTypes[creditType]) revert Errors.UnsupportedCreditType();
        LibCreditUtils.transferFunds(amount, paymentType, treasureIds, treasureAmounts);
    }

    // Upgrade inventory slots
    function upgradeInventorySlot(
        uint256 amount,
        PaymentType paymentType,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) internal {
        if (amount < 1) revert Errors.InvalidAmount();
        LibCreditUtils.transferFunds(amount, paymentType, treasureIds, treasureAmounts);
    }

    // Transfer funds depending on payment type
    function transferFunds(
        uint256 amount,
        PaymentType paymentType,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) internal {
        if (paymentType == PaymentType.TREASURES) {
            //In case of upgrade with Treasures
            LibCreditUtils.processTreasuresPayment(amount, treasureIds, treasureAmounts);
        } else if (paymentType == PaymentType.MAGIC) {
            //In case of upgrade with Magic
            LibCreditUtils.processMagicPayment(amount);
        } else if (paymentType == PaymentType.GFLY) {
            //In case of upgrade with gFLY
            LibCreditUtils.processGFlyPayment(amount);
        } else {
            revert Errors.UnsupportedPaymentType();
        }
    }

    // Process payments with Magic
    function processMagicPayment(uint256 amount) internal {
        uint256 requiredMagic = amount * gs().magicPerCredit;
        IERC20(gs().magic).transferFrom(msg.sender, address(this), requiredMagic);
        gs().magicForLp += requiredMagic;
    }

    // Process payments with gFLY
    function processGFlyPayment(uint256 amount) internal {
        uint256 requiredGFly = amount * gs().gFlyPerCredit;
        IERC20(gs().gFLY).transferFrom(msg.sender, address(this), requiredGFly);
        gs().gFlyForLp += requiredGFly;
    }

    // Process payments with treasures
    function processTreasuresPayment(
        uint256 amount,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) internal {
        if (treasureIds.length != treasureAmounts.length) revert Errors.InvalidArrayLength();
        uint256 requiredTreasures = amount * gs().treasuresPerCredit;
        uint256 receivedTreasures;
        for (uint256 i = 0; i < treasureAmounts.length; i++) {
            receivedTreasures += treasureAmounts[i];
        }
        if (requiredTreasures != receivedTreasures) revert Errors.IncorrectTreasuresAmount();
        IERC1155(gs().treasures).safeBatchTransferFrom(
            msg.sender,
            gs().treasureReceiver,
            treasureIds,
            treasureAmounts,
            "0x0"
        );
    }

    // Automatically swap Magic and gFLY into LP tokens if the Magic and/or gFLY tresholds are reached.
    // LP tokens are sent to the LP Receiver address
    function swapToLP() internal {
        (uint256 reserveMagic, uint256 reserveGFly) = LibCreditUtils.getReserves();
        uint256 magicAmount;
        uint256 gFLYAmount;
        uint256 magicForLp = gs().magicForLp;
        uint256 gFlyForLp = gs().gFlyForLp;
        // Check if we reached the Magic treshold for swaps into LP tokens
        if (magicForLp > 0 && magicForLp >= gs().magicLpTreshold) {
            gFLYAmount = IUniswapV2Router02(gs().magicSwapRouter).quote(magicForLp, reserveMagic, reserveGFly);
            magicAmount = magicForLp;
        }
        // Try another quote for the gFLY token if the gFLY treshold is reached for swaps into LP tokens and
        // the initially proposed quote is not enough to cover it.
        if (gFLYAmount > gFlyForLp && gFlyForLp > 0 && gFlyForLp >= gs().gFlyLpTreshold) {
            magicAmount = IUniswapV2Router02(gs().magicSwapRouter).quote(gFlyForLp, reserveGFly, reserveMagic);
            gFLYAmount = gFlyForLp;
        }
        // Check if we have enough Magic and gFLY to cover the proposed amounts
        if (magicAmount > 0 && gFLYAmount > 0 && magicAmount <= magicForLp && gFLYAmount <= gFlyForLp) {
            IERC20(gs().magic).approve(gs().magicSwapRouter, magicAmount);
            IERC20(gs().gFLY).approve(gs().magicSwapRouter, gFLYAmount);
            uint256 minMagic = (magicAmount * (gs().bpsDenominator - gs().slippageInBPS)) / gs().bpsDenominator;
            uint256 minGFly = (gFLYAmount * (gs().bpsDenominator - gs().slippageInBPS)) / gs().bpsDenominator;
            (uint256 providedMagic, uint256 providedGFly, uint256 liquidity) = IUniswapV2Router02(gs().magicSwapRouter)
                .addLiquidity(
                    gs().magic,
                    gs().gFLY,
                    magicAmount,
                    gFLYAmount,
                    minMagic,
                    minGFly,
                    gs().lpReceiver,
                    block.timestamp
                );
            gs().magicForLp -= providedMagic;
            gs().gFlyForLp -= providedGFly;
            emit LiquidityAdded(liquidity, providedMagic, providedGFly);
        }
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert Errors.IdenticalAddresses();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert Errors.InvalidAddress();
    }

    // fetches and sorts the reserves for a pair
    function getReserves() internal view returns (uint reserveMagic, uint reserveGFly) {
        (address token0, ) = sortTokens(gs().magic, gs().gFLY);
        (uint reserve0, uint reserve1, ) = IUniswapV2Pair(gs().magicGFlyLp).getReserves();
        (reserveMagic, reserveGFly) = gs().magic == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }
}

