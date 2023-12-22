interface IUnizenTradeV2 {
    struct SwapCall {
        address targetExchange;
        uint256 amount;
        bytes data; // Encoded data to execute the trade by contract call
    }

    struct CrossChainSwapClr {
        uint16 srcChain;
        uint16 dstChain;
        address srcToken;
        uint256 amount; // trade amount of srcToken
        bool isFromNative;
        uint256 nativeFee; // fee to LZ
    }
    event CrossChainSwapped(uint16 chainId, address user, uint256 valueInUSD);
}

