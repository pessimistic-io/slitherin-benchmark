// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IAcross.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./LibData.sol";
import "./LibPlexusUtil.sol";

contract AcrossFacet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IAcross private immutable across;

    constructor(IAcross _across) {
        across = _across;
    }

    function bridgeToAcross(AcrossData memory _acrossData) external payable nonReentrant {
        LibPlexusUtil._isTokenDeposit(_acrossData.srcToken, _acrossData.amount);
        _acrossData.amount = LibPlexusUtil._fee(_acrossData.srcToken, _acrossData.amount);
        _acrossStart(_acrossData);
    }

    function swapAndBridgeToAcross(SwapData calldata _swap, AcrossData memory _acrossData) external payable nonReentrant {
        _acrossData.amount = LibPlexusUtil._fee(_acrossData.srcToken, LibPlexusUtil._tokenDepositAndSwap(_swap));
        _acrossStart(_acrossData);
    }

    function _acrossStart(AcrossData memory _acrossData) internal {
        bool isNotNative = !LibPlexusUtil._isNative(_acrossData.srcToken);
        if (isNotNative) {
            IERC20(_acrossData.srcToken).safeApprove(address(across), _acrossData.amount);
            across.deposit{value: 0}(
                _acrossData.receiver,
                _acrossData.srcToken,
                _acrossData.amount,
                _acrossData.dstChainId,
                _acrossData.relayerFeePct,
                _acrossData.quoteTimestamp,
                _acrossData.message,
                _acrossData.maxCount
            );
            IERC20(_acrossData.srcToken).safeApprove(address(across), 0);
        } else {
            across.deposit{value: _acrossData.amount}(
                _acrossData.receiver,
                _acrossData.wrappedNative,
                _acrossData.amount,
                _acrossData.dstChainId,
                _acrossData.relayerFeePct,
                _acrossData.quoteTimestamp,
                _acrossData.message,
                _acrossData.maxCount
            );
        }

        bytes32 transferId = keccak256(
            abi.encodePacked(
                address(this),
                _acrossData.receiver,
                _acrossData.srcToken,
                _acrossData.amount,
                _acrossData.dstChainId,
                _acrossData.maxCount,
                uint64(block.chainid)
            )
        );
        emit LibData.Bridge(
            msg.sender,
            _acrossData.dstChainId,
            _acrossData.srcToken,
            _acrossData.toDstToken,
            _acrossData.amount,
            transferId,
            "Across"
        );
    }
}

