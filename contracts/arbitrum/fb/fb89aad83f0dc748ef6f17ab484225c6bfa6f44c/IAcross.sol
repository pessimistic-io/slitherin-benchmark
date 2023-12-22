pragma solidity 0.8.17;

struct AcrossData {
    int64 relayerFeePct;
    uint32 quoteTimestamp;
    uint64 dstChainId;
    uint256 maxCount;
    uint256 amount;
    address srcToken;
    address receiver;
    address wrappedNative;
    address toDstToken;
    bytes message;
}

interface IAcross {
    function deposit(
        address recipient,
        address originToken,
        uint256 amount,
        uint256 destinationChainId,
        int64 relayerFeePct,
        uint32 quoteTimestamp,
        bytes memory message,
        uint256 maxCount
    ) external payable;
}

