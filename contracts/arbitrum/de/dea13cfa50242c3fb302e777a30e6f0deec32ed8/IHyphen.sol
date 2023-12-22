pragma solidity 0.8.17;

struct HyphenDescription {
    address token;
    address receiver;
    uint256 toChainId;
    uint256 amount;
    uint64 nonce;
    address toDstToken;
}

interface IHyphen {
    function depositNative(address receiver, uint256 toChainId, string calldata tag) external payable;

    function depositErc20(uint256 toChainId, address tokenAddress, address receiver, uint256 amount, string calldata tag) external;
}

