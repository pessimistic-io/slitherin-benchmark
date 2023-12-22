pragma solidity 0.8.17;

struct ConnextData {
    uint256 slippage;
    uint256 relayerFee;
    address delegate;
}
struct TransferInfo {
    uint32 originDomain;
    uint32 destinationDomain;
    uint32 canonicalDomain;
    address to;
    address delegate;
    bool receiveLocal;
    bytes callData;
    uint256 slippage;
    address originSender;
    uint256 bridgedAmt;
    uint256 normalizedIn;
    uint256 nonce;
    bytes32 canonicalId;
}

struct DomainId {
    uint64 chainId;
    uint64 domainId;
}

interface IConnext {
    function xcall(
        uint32 _destination,
        address _to,
        address _asset,
        address _delegate,
        uint256 _amount,
        uint256 _slippage,
        bytes calldata _callData,
        uint256 _relayerFee
    ) external payable;

    function forceUpdateSlippage(TransferInfo calldata _params, uint256 _slippage) external;

    function bumpTransfer(bytes32 _transferId, address _relayerFeeAsset, uint256 _relayerFee) external payable;
}

