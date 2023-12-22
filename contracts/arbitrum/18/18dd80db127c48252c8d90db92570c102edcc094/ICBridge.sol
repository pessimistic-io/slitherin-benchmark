pragma solidity 0.8.17;

struct CBridgeDescription {
    address srcToken;
    uint256 amount;
    address receiver;
    uint64 dstChainId;
    uint64 nonce;
    uint32 maxSlippage;
    address toDstToken;
}

interface ICBridge {
    function send(address _receiver, address _token, uint256 _amount, uint64 _dstChainId, uint64 _nonce, uint32 _maxSilippage) external;

    function sendNative(address _receiver, uint256 _amount, uint64 _dstChainId, uint64 _nonce, uint32 _maxSlippage) external payable;

    function withdraw(bytes calldata _wdmsg, bytes[] memory _sigs, address[] memory _signers, uint256[] memory _powers) external;
}

