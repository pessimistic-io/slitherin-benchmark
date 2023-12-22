// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IAcross.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./LibData.sol";
import "./LibPlexusUtil.sol";
import "./console.sol";

contract AcrossFacet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IAcross private immutable across;

    constructor(IAcross _across) {
        across = _across;
    }

    function bridgeToAcross(AcrossDescription memory aDesc) external payable nonReentrant {
        LibPlexusUtil._isTokenDeposit(aDesc.srcToken, aDesc.amount);
        aDesc.amount = LibPlexusUtil._fee(aDesc.srcToken, aDesc.amount);
        _acrossStart(aDesc);
    }

    function swapAndBridgeToAcross(SwapData calldata _swap, AcrossDescription memory aDesc) external payable nonReentrant {
        aDesc.amount = LibPlexusUtil._fee(aDesc.srcToken, LibPlexusUtil._tokenDepositAndSwap(_swap));
        _acrossStart(aDesc);
    }

    function _acrossStart(AcrossDescription memory aDesc) internal {
        bool isNotNative = !LibPlexusUtil._isNative(aDesc.srcToken);
        if (isNotNative) {
            IERC20(aDesc.srcToken).safeApprove(address(across), aDesc.amount);
            across.deposit{value: 0}(
                aDesc.recipient,
                aDesc.srcToken,
                aDesc.amount,
                aDesc.dstChainId,
                aDesc.relayerFeePct,
                aDesc.quoteTimestamp,
                aDesc.message,
                aDesc.maxCount
            );
        } else {
            across.deposit{value: aDesc.amount}(
                aDesc.recipient,
                aDesc.wrappedNative,
                aDesc.amount,
                aDesc.dstChainId,
                aDesc.relayerFeePct,
                aDesc.quoteTimestamp,
                aDesc.message,
                aDesc.maxCount
            );
        }

        bytes32 transferId = keccak256(
            abi.encodePacked(address(this), aDesc.recipient, aDesc.srcToken, aDesc.amount, aDesc.dstChainId, block.timestamp, uint64(block.chainid))
        );

        emit LibData.Bridge(aDesc.recipient, uint64(aDesc.dstChainId), aDesc.srcToken, aDesc.toDstToken, aDesc.amount, transferId, "Across");
    }
}

