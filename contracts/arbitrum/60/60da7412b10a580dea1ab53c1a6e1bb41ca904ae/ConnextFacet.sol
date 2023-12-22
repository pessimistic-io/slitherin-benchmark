// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IBridge.sol";
import "./IConnext.sol";
import "./IWrappedNative.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./LibData.sol";
import "./LibPlexusUtil.sol";
import "./console.sol";

contract ConnextFacet is IBridge, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IConnext private immutable connext;
    IWrappedNative private immutable wrappedNative;

    constructor(IConnext _connext, IWrappedNative _wrappedNative) {
        connext = _connext;
        wrappedNative = _wrappedNative;
    }

    // ===== chainID & domainId match function  ====== //
    function setDomainId(DomainId[] calldata _domainMatch) external {
        require(msg.sender == LibDiamond.contractOwner());
        LibData.ConnextBridgeData storage s = LibData.connextStorage();
        for (uint64 i; i < _domainMatch.length; i++) {
            s.domainId[_domainMatch[i].chainId] = _domainMatch[i].domainId;
        }
    }

    function getDomainId(uint64 _chainId) public view returns (uint64) {
        LibData.ConnextBridgeData storage s = LibData.connextStorage();
        uint64 domainId = s.domainId[_chainId];
        return domainId;
    }

    // ======================================= //
    function bridgeToConnext(BridgeData memory _bridgeData, ConnextData memory _cnDesc) external payable nonReentrant {
        LibPlexusUtil._isTokenDeposit(_bridgeData.srcToken, _bridgeData.amount);
        _connextStart(_bridgeData, _cnDesc);
    }

    function swapAndBridgeToConnext(
        SwapData calldata _swap,
        BridgeData memory _bridgeData,
        ConnextData memory _cnDesc
    ) external payable nonReentrant {
        _bridgeData.amount = LibPlexusUtil._tokenDepositAndSwap(_swap);
        _connextStart(_bridgeData, _cnDesc);
    }

    /** update slippage */
    function connextUpdateSlippage(TransferInfo calldata _params, uint256 _slippage) external {
        connext.forceUpdateSlippage(_params, _slippage);
    }

    /** update relayerFee  */
    function connextBumpTransfer(bytes32 _transferId, address _relayerFeeAsset, uint256 _relayerFee) external payable {
        LibPlexusUtil._isTokenDeposit(_relayerFeeAsset, _relayerFee);
        connext.bumpTransfer(_transferId, _relayerFeeAsset, _relayerFee);
    }

    function _connextStart(BridgeData memory _bridgeData, ConnextData memory _cnDesc) internal {
        bool isNotNative = !LibPlexusUtil._isNative(_bridgeData.srcToken);
        if (isNotNative) {
            IERC20(_bridgeData.srcToken).safeApprove(address(connext), _bridgeData.amount);
            connext.xcall(
                uint32(getDomainId(_bridgeData.dstChainId)),
                _bridgeData.recipient,
                _bridgeData.srcToken,
                _cnDesc.delegate,
                _bridgeData.amount - _cnDesc.relayerFee,
                _cnDesc.slippage,
                "",
                _cnDesc.relayerFee
            );
            IERC20(_bridgeData.srcToken).safeApprove(address(connext), 0);
        } else {
            wrappedNative.deposit{value: msg.value}();
            IERC20(address(wrappedNative)).safeApprove(address(connext), _bridgeData.amount);
            _bridgeData.srcToken = address(wrappedNative);
            connext.xcall(
                uint32(getDomainId(_bridgeData.dstChainId)),
                _bridgeData.recipient,
                _bridgeData.srcToken,
                _cnDesc.delegate,
                _bridgeData.amount - _cnDesc.relayerFee,
                _cnDesc.slippage,
                "",
                _cnDesc.relayerFee
            );
            IERC20(address(wrappedNative)).safeApprove(address(connext), 0);
        }

        emit LibData.Bridge(msg.sender, _bridgeData.dstChainId, _bridgeData.srcToken, _bridgeData.amount, _bridgeData.plexusData);
    }
}

