interface IUnizenDexAggr {
    struct SwapCall {
        address targetExchange;
        uint256 amount;
        bytes data; // Encoded data to execute the trade by contract call
    }

    struct SwapExactInInfo {
        address sender; // Sender address
        address receiver; // Receiver address
        address srcToken; //Input token
        address dstToken; //Output token
        uint256 amountIn; // amount in user want to trade
        uint256 amountOutMin; // expected amount out min
    }

    struct SwapExactOutInfo {
        address sender; // Sender address
        address receiver; // Receiver address
        address srcToken; //Input token
        address dstToken; //Output token
        uint256 amountOut; // expect amount out of user
        uint256 amountInMax; //amount in max that user willing to pay
    }

    struct CrossChainSwapLz {
        uint16 dstChain; // dstChainId in LZ - not network chain id
        bool isFromNative;
        uint256 amount; // trade amount of srcToken
        uint256 nativeFee; // fee to LZ
        address srcToken;
        bytes adapterParams;
    }

    struct CrossChainSwapSg {
        uint16 dstChain; // dstChainId in LZ - not network chain id
        uint16 srcPool; // src stable pool id
        uint16 dstPool; // dst stable pool id
        bool isFromNative;
        address srcToken;
        uint256 amount;
        uint256 nativeFee; // fee to LZ
        bool isAmountOut; // true if the swap is exactOut
    }

    struct SplitTrade {
        uint16 dstChain; // dstChainId in LZ - not network chain id
        uint16 srcPool; // src stable pool id
        uint16 dstPool; // dst stable pool id
        uint256[2] amount; // amount of srcToken
        uint256 bridgeAmount; // amount of stable token want to swap to destination chain
        uint256 amountOutMinSrc;
        uint256 amountOutMin; // amountOutMin on destination chain
        uint256 nativeFee; // fee to LZ
        address[] pathToken; // path to token out
        address[] pathStable; // path to stable
        address[] pathDstChain; // path trade on dst chain
    }

    struct CallBackTrade {
        uint16 dstChain; // dstChainId in LZ - not network chain id
        uint16 srcPool; // src stable pool id
        uint16 dstPool; // dst stable pool id
        uint256 amount; // amount of srcToken
        uint256 amountOutMinSrc;
        uint256 nativeFee; // fee to LZ
        address[] dstExchange;
        bytes[] dstExchangeData;
        address[] pathSrcChain; // path to stable
    }

    struct ContractStatus {
        uint256 balanceDstBefore;
        uint256 balanceDstAfter;
        uint256 balanceSrcBefore;
        uint256 balanceSrcAfter;
    }

    event Swapped(
        uint256 amountIn,
        uint256 amountOut,
        address srcToken,
        address dstToken,
        address receiver,
        address sender
    );

    event CrossChainSwapped(uint16 chainId, address user, uint256 valueInUSD);
}

