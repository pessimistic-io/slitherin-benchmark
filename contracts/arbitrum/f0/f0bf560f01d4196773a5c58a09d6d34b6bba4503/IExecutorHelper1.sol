// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IHashflow.sol";

interface IExecutorHelper1 {
    struct UniSwap {
        address pool;
        address tokenIn;
        address tokenOut;
        address recipient;
        uint256 collectAmount; // amount that should be transferred to the pool
        uint256 limitReturnAmount;
        uint32 swapFee;
        uint32 feePrecision;
        uint32 tokenWeightInput;
    }

    struct StableSwap {
        address pool;
        address tokenFrom;
        address tokenTo;
        uint8 tokenIndexFrom;
        uint8 tokenIndexTo;
        uint256 dx;
        uint256 minDy;
        uint256 poolLength;
        address poolLp;
        bool isSaddle; // true: saddle, false: stable
    }

    struct CurveSwap {
        address pool;
        address tokenFrom;
        address tokenTo;
        int128 tokenIndexFrom;
        int128 tokenIndexTo;
        uint256 dx;
        uint256 minDy;
        bool usePoolUnderlying;
        bool useTriCrypto;
    }

    struct UniSwapV3ProMM {
        address recipient;
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 swapAmount;
        uint256 limitReturnAmount;
        uint160 sqrtPriceLimitX96;
        bool isUniV3; // true = UniV3, false = ProMM
    }
    struct SwapCallbackData {
        bytes path;
        address payer;
    }
    struct SwapCallbackDataPath {
        address pool;
        address tokenIn;
        address tokenOut;
    }

    struct BalancerV2 {
        address vault;
        bytes32 poolId;
        address assetIn;
        address assetOut;
        uint256 amount;
        uint256 limit;
    }

    struct KyberRFQ {
        address rfq;
        bytes order;
        bytes signature;
        uint256 amount;
        address payable target;
    }

    struct DODO {
        address recipient;
        address pool;
        address tokenFrom;
        address tokenTo;
        uint256 amount;
        uint256 minReceiveQuote;
        address sellHelper;
        bool isSellBase;
        bool isVersion2;
    }

    struct GMX {
        address vault;
        address tokenIn;
        address tokenOut;
        uint256 amount;
        uint256 minOut;
        address receiver;
    }

    struct Synthetix {
        address synthetixProxy;
        address tokenIn;
        address tokenOut;
        bytes32 sourceCurrencyKey;
        uint256 sourceAmount;
        bytes32 destinationCurrencyKey;
        uint256 minAmount;
        bool useAtomicExchange;
    }

    struct Hashflow {
        address router;
        IHashflow.Quote quote;
    }

    function executeUniSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeStableSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeCurveSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeKyberDMMSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeUniV3ProMMSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeRfqSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeBalV2Swap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeDODOSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeVelodromeSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeGMXSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeSynthetixSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeHashflowSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeCamelotSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);
}

