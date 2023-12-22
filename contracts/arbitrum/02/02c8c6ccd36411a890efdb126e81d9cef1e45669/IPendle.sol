// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";

interface IPRouter {
    struct TokenInput {
        address tokenIn;
        uint256 netTokenIn;
        address tokenMintSy;
        address bulk;
        address pendleSwap;
        IPSwapAggregator.SwapData swapData;
    }

    struct TokenOutput {
        address tokenOut;
        uint256 minTokenOut;
        address tokenRedeemSy;
        address bulk;
        address pendleSwap;
        IPSwapAggregator.SwapData swapData;
    }

    function addLiquiditySingleToken(
        address receiver,
        address market,
        uint256 minLpOut,
        IPMarket.ApproxParams calldata guessPtReceivedFromSy,
        TokenInput calldata input
    ) external payable returns (uint256 netLpOut, uint256 netSyFee);
    function removeLiquiditySingleToken(
        address receiver,
        address market,
        uint256 netLpToRemove,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut, uint256 netSyFee);
}

interface IPSwapAggregator {
    enum SwapType {
        NONE,
        KYBERSWAP,
        ONE_INCH,
        ETH_WETH
    }

    struct SwapData {
        SwapType swapType;
        address extRouter;
        bytes extCalldata;
        bool needScale;
    }
}

interface IPMarket is IERC20 {
    struct ApproxParams {
        uint256 guessMin; // The minimum value for binary search.
        uint256 guessMax; // The maximum value for binary search.
        uint256 guessOffchain; // This is the first answer to be checked before performing any binary search. If the answer already satisfies, Pendle skip the search and save significant gas.
        uint256 maxIteration; // The maximum number of times binary search will be performed.
        uint256 eps; // The precision of binary search - the maximum proportion of the input that can be unused. eps is 1e18-based, so an eps of 1e14 implies that no more than 0.01% of the input might be unused.
    }

    function redeemRewards(address user) external returns (uint256[] memory);
    function getRewardTokens() external view returns (address[] memory);
}

interface ILpOracleHelper {
    function getLpToAssetRate(IPMarket market, uint32 duration) external view returns (uint256 lpToAssetRate);
}

