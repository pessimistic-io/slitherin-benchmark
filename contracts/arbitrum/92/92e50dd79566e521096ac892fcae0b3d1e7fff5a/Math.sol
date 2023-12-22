// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IMath.sol";

import "./MayfairConstants.sol";
import "./MayfairSafeMath.sol";

/**
 * @title Math functions for price, balance and swap calculations
 */
abstract contract Math is IMath {
    /**
     * @notice Get the spot price between two assets
     *
     * @param tokenBalanceIn - Balance of the swapped-in token inside the Pool
     * @param tokenWeightIn - Denormalized weight of the swapped-in token inside the Pool
     * @param tokenBalanceOut - Balance of the swapped-out token inside the Pool
     * @param tokenWeightOut - Denormalized weight of the swapped-out token inside the Pool
     * @param swapFee - Fee for performing swap (percentage)
     *
     * @return Spot price as amount of swapped-in for every swapped-out
     *
     ***********************************************************************************************
     // calcSpotPrice                                                                             //
     // sP = spotPrice                                                                            //
     // bI = tokenBalanceIn                ( bI / wI )         1                                  //
     // bO = tokenBalanceOut         sP =  -----------  *  ----------                             //
     // wI = tokenWeightIn                 ( bO / wO )     ( 1 - sF )                             //
     // wO = tokenWeightOut                                                                       //
     // sF = swapFee                                                                              //
     **********************************************************************************************/
    function calcSpotPrice(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint swapFee
    ) public pure returns (uint) {
        uint numer = MayfairSafeMath.bdiv(tokenBalanceIn, tokenWeightIn);
        uint denom = MayfairSafeMath.bdiv(tokenBalanceOut, tokenWeightOut);
        uint ratio = MayfairSafeMath.bdiv(numer, denom);
        uint scale = MayfairSafeMath.bdiv(
            MayfairConstants.ONE,
            (MayfairConstants.ONE - swapFee)
        );
        return MayfairSafeMath.bmul(ratio, scale);
    }

    /**
     * @notice Get amount received when sending an exact amount on swap
     *
     * @param tokenBalanceIn - Balance of the swapped-in token inside the Pool
     * @param tokenWeightIn - Denormalized weight of the swapped-in token inside the Pool
     * @param tokenBalanceOut - Balance of the swapped-out token inside the Pool
     * @param tokenWeightOut - Denormalized weight of the swapped-out token inside the Pool
     * @param tokenAmountIn - Amount of swapped-in token that will be sent
     * @param swapFee - Fee for performing swap (percentage)
     *
     * @return Amount of swapped-out token you'll receive
     *
     ***********************************************************************************************
     // calcOutGivenIn                                                                            //
     // aO = tokenAmountOut                                                                       //
     // bO = tokenBalanceOut                                                                      //
     // bI = tokenBalanceIn              /      /            bI             \    (wI / wO) \      //
     // aI = tokenAmountIn    aO = bO * |  1 - | --------------------------  | ^            |     //
     // wI = tokenWeightIn               \      \ ( bI + ( aI * ( 1 - sF )) /              /      //
     // wO = tokenWeightOut                                                                       //
     // sF = swapFee                                                                              //
     **********************************************************************************************/
    function calcOutGivenIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountIn,
        uint swapFee
    ) public pure returns (uint) {
        uint weightRatio = MayfairSafeMath.bdiv(tokenWeightIn, tokenWeightOut);
        uint adjustedIn = MayfairConstants.ONE - swapFee;
        adjustedIn = MayfairSafeMath.bmul(tokenAmountIn, adjustedIn);
        uint y = MayfairSafeMath.bdiv(
            tokenBalanceIn,
            (tokenBalanceIn + adjustedIn)
        );
        uint foo = MayfairSafeMath.bpow(y, weightRatio);
        uint bar = MayfairConstants.ONE - foo;
        return MayfairSafeMath.bmul(tokenBalanceOut, bar);
    }

    /**
     * @notice Get amount that must be sent to receive an exact amount on swap
     *
     * @param tokenBalanceIn - Balance of the swapped-in token inside the Pool
     * @param tokenWeightIn - Denormalized weight of the swapped-in token inside the Pool
     * @param tokenBalanceOut - Balance of the swapped-out token inside the Pool
     * @param tokenWeightOut - Denormalized weight of the swapped-out token inside the Pool
     * @param tokenAmountOut - Amount of swapped-out token that you want to receive
     * @param swapFee - Fee for performing swap (percentage)
     *
     * @return Amount of swapped-in token to send
     *
     ***********************************************************************************************
     // calcInGivenOut                                                                            //
     // aI = tokenAmountIn                                                                        //
     // bO = tokenBalanceOut               /  /     bO      \    (wO / wI)      \                 //
     // bI = tokenBalanceIn          bI * |  | ------------  | ^            - 1  |                //
     // aO = tokenAmountOut    aI =        \  \ ( bO - aO ) /                   /                 //
     // wI = tokenWeightIn           --------------------------------------------                 //
     // wO = tokenWeightOut                          ( 1 - sF )                                   //
     // sF = swapFee                                                                              //
     **********************************************************************************************/
    function calcInGivenOut(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountOut,
        uint swapFee
    ) public pure returns (uint) {
        uint weightRatio = MayfairSafeMath.bdiv(tokenWeightOut, tokenWeightIn);
        uint diff = tokenBalanceOut - tokenAmountOut;
        uint y = MayfairSafeMath.bdiv(tokenBalanceOut, diff);
        uint foo = MayfairSafeMath.bpow(y, weightRatio);
        foo = foo - MayfairConstants.ONE;
        return
            MayfairSafeMath.bdiv(
                MayfairSafeMath.bmul(tokenBalanceIn, foo),
                MayfairConstants.ONE - swapFee
            );
    }

    /**
     * @notice Get amount of pool tokens received when sending an exact amount of a single token
     *
     * @param tokenBalanceIn - Balance of the swapped-in token inside the Pool
     * @param tokenWeightIn - Denormalized weight of the swapped-in token inside the Pool
     * @param poolSupply - Current supply of the pool token
     * @param totalWeight - Total denormalized weight of the pool
     * @param tokenAmountIn - Amount of swapped-in token that will be sent
     * @param swapFee - Fee for performing swap (percentage)
     *
     * @return Amount of the pool token you'll receive
     *
     ***********************************************************************************************
     // calcPoolOutGivenSingleIn                                                                  //
     // pAo = poolAmountOut         /                                              \              //
     // tAi = tokenAmountIn        ///      /     //    wI \      \\       \     wI \             //
     // wI = tokenWeightIn        //| tAi *| 1 - || 1 - --  | * sF || + tBi \    --  \            //
     // tW = totalWeight     pAo=||  \      \     \\    tW /      //         | ^ tW   | * pS - pS //
     // tBi = tokenBalanceIn      \\  ------------------------------------- /        /            //
     // pS = poolSupply            \\                    tBi               /        /             //
     // sF = swapFee                \                                              /              //
     **********************************************************************************************/
    function calcPoolOutGivenSingleIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountIn,
        uint swapFee
    ) public pure override returns (uint) {
        // Charge the trading fee for the proportion of tokenAi
        //   which is implicitly traded to the other pool tokens.
        // That proportion is (1- weightTokenIn)
        // tokenAiAfterFee = tAi * (1 - (1-weightTi) * poolFee);
        uint normalizedWeight = MayfairSafeMath.bdiv(
            tokenWeightIn,
            totalWeight
        );
        uint zaz = MayfairSafeMath.bmul(
            (MayfairConstants.ONE - normalizedWeight),
            swapFee
        );
        uint tokenAmountInAfterFee = MayfairSafeMath.bmul(
            tokenAmountIn,
            (MayfairConstants.ONE - zaz)
        );

        uint newTokenBalanceIn = tokenBalanceIn + tokenAmountInAfterFee;
        uint tokenInRatio = MayfairSafeMath.bdiv(
            newTokenBalanceIn,
            tokenBalanceIn
        );

        // uint newPoolSupply = (ratioTi ^ weightTi) * poolSupply;
        uint poolRatio = MayfairSafeMath.bpow(tokenInRatio, normalizedWeight);
        uint newPoolSupply = MayfairSafeMath.bmul(poolRatio, poolSupply);
        return newPoolSupply - poolSupply;
    }

    /**
     * @notice Get amount that must be sent of a single token to receive an exact amount of pool tokens
     *
     * @param tokenBalanceIn - Balance of the swapped-in token inside the Pool
     * @param tokenWeightIn - Denormalized weight of the swapped-in token inside the Pool
     * @param poolSupply - Current supply of the pool token
     * @param totalWeight - Total denormalized weight of the pool
     * @param poolAmountOut - Amount of pool tokens that you want to receive
     * @param swapFee - Fee for performing swap (percentage)
     *
     * @return Amount of swapped-in tokens to send
     *
     ***********************************************************************************************
     // calcSingleInGivenPoolOut                                                                  //
     // tAi = tokenAmountIn              //(pS + pAo)\     /    1    \\                           //
     // pS = poolSupply                 || ---------  | ^ | --------- || * bI - bI                //
     // pAo = poolAmountOut              \\    pS    /     \(wI / tW)//                           //
     // bI = balanceIn          tAi =  --------------------------------------------               //
     // wI = weightIn                              /      wI  \                                   //
     // tW = totalWeight                          |  1 - ----  |  * sF                            //
     // sF = swapFee                               \      tW  /                                   //
     **********************************************************************************************/
    function calcSingleInGivenPoolOut(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountOut,
        uint swapFee
    ) public pure override returns (uint) {
        uint normalizedWeight = MayfairSafeMath.bdiv(
            tokenWeightIn,
            totalWeight
        );
        uint newPoolSupply = poolSupply + poolAmountOut;
        uint poolRatio = MayfairSafeMath.bdiv(newPoolSupply, poolSupply);

        //uint newBalTi = poolRatio^(1/weightTi) * balTi;
        uint boo = MayfairSafeMath.bdiv(MayfairConstants.ONE, normalizedWeight);
        uint tokenInRatio = MayfairSafeMath.bpow(poolRatio, boo);
        uint newTokenBalanceIn = MayfairSafeMath.bmul(
            tokenInRatio,
            tokenBalanceIn
        );
        uint tokenAmountInAfterFee = newTokenBalanceIn - tokenBalanceIn;
        // Do reverse order of fees charged in joinswap_ExternAmountIn, this way
        //     ``` pAo == joinswap_ExternAmountIn(Ti, joinswap_PoolAmountOut(pAo, Ti)) ```
        //uint tAi = tAiAfterFee / (1 - (1-weightTi) * swapFee) ;
        uint zar = MayfairSafeMath.bmul(
            (MayfairConstants.ONE - normalizedWeight),
            swapFee
        );
        return
            MayfairSafeMath.bdiv(
                tokenAmountInAfterFee,
                (MayfairConstants.ONE - zar)
            );
    }

    /**
     * @notice Get amount received of a single token when sending an exact amount of pool tokens
     *
     * @param tokenBalanceOut - Balance of the swapped-out token inside the Pool
     * @param tokenWeightOut - Denormalized weight of the swapped-out token inside the Pool
     * @param poolSupply - Current supply of the pool token
     * @param totalWeight - Total denormalized weight of the pool
     * @param poolAmountIn - Amount of pool tokens that will be sent
     * @param swapFee - Fee for performing swap (percentage)
     * @param exitFee - Fee for exiting the pool (percentage)
     *
     * @return Amount of the swapped-out token you'll receive
     *
     ***********************************************************************************************
     // calcSingleOutGivenPoolIn                                                                  //
     // tAo = tokenAmountOut            /      /                                             \\   //
     // bO = tokenBalanceOut           /      // pS - (pAi * (1 - eF)) \     /    1    \      \\  //
     // pAi = poolAmountIn            | bO - || ----------------------- | ^ | --------- | * b0 || //
     // ps = poolSupply                \      \\          pS           /     \(wO / tW)/      //  //
     // wI = tokenWeightIn      tAo =   \      \                                             //   //
     // tW = totalWeight                    /     /      wO \       \                             //
     // sF = swapFee                    *  | 1 - |  1 - ---- | * sF  |                            //
     // eF = exitFee                        \     \      tW /       /                             //
     **********************************************************************************************/
    function calcSingleOutGivenPoolIn(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountIn,
        uint swapFee,
        uint exitFee
    ) public pure override returns (uint) {
        uint normalizedWeight = MayfairSafeMath.bdiv(
            tokenWeightOut,
            totalWeight
        );
        // charge exit fee on the pool token side
        // pAiAfterExitFee = pAi*(1-exitFee)
        uint poolAmountInAfterExitFee = MayfairSafeMath.bmul(
            poolAmountIn,
            (MayfairConstants.ONE - exitFee)
        );
        uint newPoolSupply = poolSupply - poolAmountInAfterExitFee;
        uint poolRatio = MayfairSafeMath.bdiv(newPoolSupply, poolSupply);

        // newBalTo = poolRatio^(1/weightTo) * balTo;
        uint tokenOutRatio = MayfairSafeMath.bpow(
            poolRatio,
            MayfairSafeMath.bdiv(MayfairConstants.ONE, normalizedWeight)
        );
        uint newTokenBalanceOut = MayfairSafeMath.bmul(
            tokenOutRatio,
            tokenBalanceOut
        );

        uint tokenAmountOutBeforeSwapFee = tokenBalanceOut - newTokenBalanceOut;

        // charge swap fee on the output token side
        //uint tAo = tAoBeforeSwapFee * (1 - (1-weightTo) * swapFee)
        uint zaz = MayfairSafeMath.bmul(
            (MayfairConstants.ONE - normalizedWeight),
            swapFee
        );
        return
            MayfairSafeMath.bmul(
                tokenAmountOutBeforeSwapFee,
                (MayfairConstants.ONE - zaz)
            );
    }

    /**
     * @notice Get amount that must be sent of pool tokens to receive an exact amount of a single token
     *
     * @param tokenBalanceOut - Balance of the swapped-out token inside the Pool
     * @param tokenWeightOut - Denormalized weight of the swapped-out token inside the Pool
     * @param poolSupply - Current supply of the pool token
     * @param totalWeight - Total denormalized weight of the pool
     * @param tokenAmountOut - Amount of swapped-out token that you want to receive
     * @param swapFee - Fee for performing swap (percentage)
     * @param exitFee - Fee for exiting the pool (percentage)
     *
     * @return Amount of pool tokens to send
     *
     ***********************************************************************************************
     // calcPoolInGivenSingleOut                                                                  //
     // pAi = poolAmountIn               // /               tAo             \\     / wO \     \   //
     // bO = tokenBalanceOut            // | bO - -------------------------- |\   | ---- |     \  //
     // tAo = tokenAmountOut      pS - ||   \     1 - ((1 - (tO / tW)) * sF)/  | ^ \ tW /  * pS | //
     // ps = poolSupply                 \\ -----------------------------------/                /  //
     // wO = tokenWeightOut  pAi =       \\               bO                 /                /   //
     // tW = totalWeight           -------------------------------------------------------------  //
     // sF = swapFee                                        ( 1 - eF )                            //
     // eF = exitFee                                                                              //
     **********************************************************************************************/
    function calcPoolInGivenSingleOut(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountOut,
        uint swapFee,
        uint exitFee
    ) public pure override returns (uint) {
        // charge swap fee on the output token side
        uint normalizedWeight = MayfairSafeMath.bdiv(
            tokenWeightOut,
            totalWeight
        );
        //uint tAoBeforeSwapFee = tAo / (1 - (1-weightTo) * swapFee) ;
        uint zoo = MayfairConstants.ONE - normalizedWeight;
        uint zar = MayfairSafeMath.bmul(zoo, swapFee);
        uint tokenAmountOutBeforeSwapFee = MayfairSafeMath.bdiv(
            tokenAmountOut,
            (MayfairConstants.ONE - zar)
        );

        uint newTokenBalanceOut = tokenBalanceOut - tokenAmountOutBeforeSwapFee;
        uint tokenOutRatio = MayfairSafeMath.bdiv(
            newTokenBalanceOut,
            tokenBalanceOut
        );

        //uint newPoolSupply = (ratioTo ^ weightTo) * poolSupply;
        uint poolRatio = MayfairSafeMath.bpow(tokenOutRatio, normalizedWeight);
        uint newPoolSupply = MayfairSafeMath.bmul(poolRatio, poolSupply);
        uint poolAmountInAfterExitFee = poolSupply - newPoolSupply;

        // charge exit fee on the pool token side
        // pAi = pAiAfterExitFee/(1-exitFee)
        return
            MayfairSafeMath.bdiv(
                poolAmountInAfterExitFee,
                (MayfairConstants.ONE - exitFee)
            );
    }
}

