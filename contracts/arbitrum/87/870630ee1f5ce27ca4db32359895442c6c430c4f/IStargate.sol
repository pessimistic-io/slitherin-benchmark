pragma solidity 0.8.17;

struct Pool {
    address token;
    uint16 poolId;
}

struct ChainId {
    uint256 chainId;
    uint16 layerZeroChainId;
}

struct lzTxObj {
    uint256 dstGasForCall;
    uint256 dstNativeAmount;
    bytes dstNativeAddr;
}

struct SwapObj {
    uint256 amount;
    uint256 eqfee;
    uint256 eqReward;
    uint256 lpFee;
    uint256 protocolFee;
    uint256 lkbRemove;
}

struct StargateDescription {
    address srcToken;
    uint256 dstPoolId;
    uint256 dstChainId;
    address receiver;
    uint256 amount;
    uint256 minAmount;
    uint256 fee;
    bytes payload;
    bytes plexusData;
}

interface IStargate {
    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        lzTxObj memory _lzTxParams,
        bytes calldata _to,
        bytes calldata _payload
    ) external payable;

    function swapETH(
        uint16 _dstChainId,
        address payable _refundAddress,
        bytes calldata _toAddress,
        uint256 _amountLD,
        uint256 _mintAmountLD
    ) external payable;

    function quoteLayerZeroFee(
        uint16 _dstChainId,
        uint8 _functionType,
        bytes calldata _toAddress,
        bytes calldata _transferAndCallPayload,
        lzTxObj memory _lzTxParams
    ) external view returns (uint256, uint256);

    function getFees(
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        uint16 _dstChainId,
        address _from,
        uint256 _amountSD
    ) external view returns (SwapObj memory);
}

