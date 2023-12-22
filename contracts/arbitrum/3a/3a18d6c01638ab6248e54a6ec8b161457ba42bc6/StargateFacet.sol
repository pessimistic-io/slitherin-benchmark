pragma solidity 0.8.17;

import "./IStargate.sol";
import "./LibDiamond.sol";
import "./LibData.sol";
import "./LibPlexusUtil.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Signers.sol";
import "./VerifySigEIP712.sol";

interface IStargateFeeLibrary {
    function getFees(
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        uint16 _dstChainId,
        address _from,
        uint256 _amountSD
    ) external view returns (SwapObj memory);
}

interface IStargateWidget {
    function partnerSwap(bytes2 _partnerId) external;
}

contract StargateFacet is ReentrancyGuard, Signers, VerifySigEIP712 {
    using SafeERC20 for IERC20;
    bytes32 internal constant NAMESPACE = keccak256("com.plexus.facets.stargate");
    IStargate private immutable stargate;
    IStargate private immutable stargateETH;
    IStargateFeeLibrary private immutable feeLibrary;
    IStargateWidget private immutable widget;

    constructor(IStargate _stargate, IStargate _stargateETH, IStargateFeeLibrary _feeLibrary, IStargateWidget _widget) {
        stargate = _stargate;
        stargateETH = _stargateETH;
        feeLibrary = _feeLibrary;
        widget = _widget;
    }

    function bridgeToStargate(StargateDescription memory sDesc) external payable nonReentrant {
        LibPlexusUtil._isTokenDeposit(sDesc.srcToken, sDesc.amount);
        sDesc.amount = LibPlexusUtil._fee(sDesc.srcToken, sDesc.amount);
        _stargateStart(sDesc);
    }

    function swapAndBridgeToStargate(SwapData calldata _swap, StargateDescription memory sDesc) external payable nonReentrant {
        sDesc.amount = LibPlexusUtil._fee(sDesc.srcToken, LibPlexusUtil._tokenDepositAndSwap(_swap));
        _stargateStart(sDesc);
    }

    function initStargate(Pool[] calldata _poolId, ChainId[] calldata _chainId) external {
        require(msg.sender == LibDiamond.contractOwner());
        LibData.StargateData storage s = LibData.stargateStorage();

        for (uint256 i; i < _poolId.length; i++) {
            if (_poolId[i].token == address(0)) {
                revert();
            }
            s.poolId[_poolId[i].token] = _poolId[i].poolId;
        }

        for (uint256 i; i < _chainId.length; i++) {
            s.layerZeroId[_chainId[i].chainId] = _chainId[i].layerZeroChainId;
        }
    }

    function _stargateStart(StargateDescription memory sDesc) internal {
        bool isNotNative = !LibPlexusUtil._isNative(sDesc.srcToken);

        if (isNotNative) {
            if (IERC20(sDesc.srcToken).allowance(address(this), address(stargate)) > 0) {
                IERC20(sDesc.srcToken).safeApprove(address(stargate), 0);
            }
            IERC20(sDesc.srcToken).safeIncreaseAllowance(address(stargate), sDesc.amount);

            stargate.swap{value: sDesc.fee}(
                stargateLayerZeroId(sDesc.dstChainId),
                stargatePoolId(sDesc.srcToken),
                sDesc.dstPoolId,
                payable(msg.sender),
                sDesc.amount,
                sDesc.minAmount,
                lzTxObj(0, 0, abi.encodePacked(sDesc.receiver)),
                abi.encodePacked(sDesc.receiver),
                sDesc.payload
            );
        } else {
            if (block.chainid == 10 || block.chainid == 1 || block.chainid == 42161) {
                stargateETH.swapETH{value: sDesc.amount + sDesc.fee}(
                    stargateLayerZeroId(sDesc.dstChainId),
                    payable(msg.sender),
                    abi.encodePacked(sDesc.receiver),
                    sDesc.amount,
                    sDesc.minAmount
                );
            } else {
                stargate.swap{value: sDesc.amount + sDesc.fee}(
                    stargateLayerZeroId(sDesc.dstChainId),
                    stargatePoolId(sDesc.srcToken),
                    sDesc.dstPoolId,
                    payable(msg.sender),
                    sDesc.amount,
                    sDesc.minAmount,
                    lzTxObj(0, 0, abi.encodePacked(sDesc.receiver)),
                    abi.encodePacked(sDesc.receiver),
                    sDesc.payload
                );
            }
        }

        widget.partnerSwap(0x0016);

        bytes32 transferId = keccak256(
            abi.encodePacked(address(this), sDesc.receiver, sDesc.srcToken, sDesc.amount, sDesc.dstChainId, sDesc.nonce, uint64(block.chainid))
        );

        emit LibData.Bridge(sDesc.receiver, uint64(sDesc.dstChainId), sDesc.srcToken, sDesc.toDstToken, sDesc.amount, transferId, "Stargate");
    }

    function getLayerZeroFee(uint16 _dstChainId, bytes calldata _toAddress) external view returns (uint256) {
        (uint256 fee, ) = stargate.quoteLayerZeroFee(stargateLayerZeroId(_dstChainId), 1, _toAddress, "0x", lzTxObj(0, 0, _toAddress));
        return fee;
    }

    function getFee(
        address _srcToken,
        uint256 _dstPoolId,
        uint256 _dstChainId,
        address _from,
        uint256 _amountSD
    ) external view returns (SwapObj memory s) {
        uint16 dstChainId = stargateLayerZeroId(_dstChainId);
        uint256 srcPoolId = stargatePoolId(_srcToken);
        s = feeLibrary.getFees(srcPoolId, _dstPoolId, dstChainId, _from, _amountSD);
        return s;
    }

    function stargatePoolId(address token) public view returns (uint16) {
        LibData.StargateData storage s = LibData.stargateStorage();
        uint16 poolId = s.poolId[token];
        if (poolId == 0) revert();
        return poolId;
    }

    function stargateLayerZeroId(uint256 _chainId) public view returns (uint16) {
        LibData.StargateData storage s = LibData.stargateStorage();
        uint16 chainId = s.layerZeroId[_chainId];
        if (chainId == 0) revert();
        return chainId;
    }
}

