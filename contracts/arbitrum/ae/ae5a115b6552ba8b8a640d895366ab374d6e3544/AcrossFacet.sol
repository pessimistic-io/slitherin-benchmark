// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IBridge.sol";
import "./IAcross.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./LibData.sol";
import "./LibPlexusUtil.sol";
import "./console.sol";

contract AcrossFacet is IBridge, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IAcross private immutable across;

    constructor(IAcross _across) {
        across = _across;
    }

    function bridgeToAcross(BridgeData memory _bridgeData, AcrossData memory _acrossData) external payable nonReentrant {
        LibPlexusUtil._isTokenDeposit(_bridgeData.srcToken, _bridgeData.amount);
        _acrossStart(_bridgeData, _acrossData);
    }

    function swapAndBridgeToAcross(
        SwapData calldata _swap,
        BridgeData memory _bridgeData,
        AcrossData memory _acrossData
    ) external payable nonReentrant {
        _bridgeData.amount = LibPlexusUtil._tokenDepositAndSwap(_swap);
        _acrossStart(_bridgeData, _acrossData);
    }

    function _acrossStart(BridgeData memory _bridgeData, AcrossData memory _acrossData) internal {
        bool isNotNative = !LibPlexusUtil._isNative(_bridgeData.srcToken);
        if (isNotNative) {
            IERC20(_bridgeData.srcToken).safeApprove(address(across), _bridgeData.amount);
            across.deposit{value: 0}(
                _bridgeData.recipient,
                _bridgeData.srcToken,
                _bridgeData.amount,
                _bridgeData.dstChainId,
                _acrossData.relayerFeePct,
                _acrossData.quoteTimestamp,
                _acrossData.message,
                _acrossData.maxCount
            );
            IERC20(_bridgeData.srcToken).safeApprove(address(across), 0);
        } else {
            across.deposit{value: _bridgeData.amount}(
                _bridgeData.recipient,
                _acrossData.wrappedNative,
                _bridgeData.amount,
                _bridgeData.dstChainId,
                _acrossData.relayerFeePct,
                _acrossData.quoteTimestamp,
                _acrossData.message,
                _acrossData.maxCount
            );
        }

        emit LibData.Bridge(msg.sender, _bridgeData.dstChainId, _bridgeData.srcToken, _bridgeData.amount, _bridgeData.plexusData);
    }
}

