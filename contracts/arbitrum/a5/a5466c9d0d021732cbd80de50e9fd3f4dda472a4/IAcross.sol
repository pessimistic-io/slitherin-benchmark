pragma solidity 0.8.17;

struct AcrossData {
    int64 relayerFeePct;
    uint32 quoteTimestamp;
    bytes message;
    uint256 maxCount;
    address wrappedNative;
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

