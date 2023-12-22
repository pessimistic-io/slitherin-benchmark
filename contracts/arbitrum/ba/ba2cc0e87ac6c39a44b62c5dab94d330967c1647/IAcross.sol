pragma solidity 0.8.17;

struct AcrossDescription {
    int64 relayerFeePct;
    uint32 quoteTimestamp;
    uint256 dstChainId;
    uint256 maxCount;
    uint256 amount;
    address srcToken;
    address recipient;
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

