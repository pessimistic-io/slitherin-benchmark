pragma solidity 0.8.17;

import "./LibDiamond.sol";
import "./LibData.sol";
import "./LibPlexusUtil.sol";
import "./SafeERC20.sol";
import "./IHyphen.sol";
import "./IBridge.sol";
import "./ReentrancyGuard.sol";
import "./Signers.sol";
import "./VerifySigEIP712.sol";

contract HyphenFacet is IBridge, ReentrancyGuard, Signers, VerifySigEIP712 {
    using SafeERC20 for IERC20;
    IHyphen private immutable HYPHEN;

    constructor(IHyphen _hyphen) {
        HYPHEN = _hyphen;
    }

    function bridgeToHyphen(BridgeData memory _bridgeData) external payable nonReentrant {
        LibPlexusUtil._isTokenDeposit(_bridgeData.srcToken, _bridgeData.amount);
        _hyphenStart(_bridgeData);
    }

    function swapAndBridgeToHyphen(SwapData calldata _swap, BridgeData memory _bridgeData) external payable nonReentrant {
        _bridgeData.amount = LibPlexusUtil._tokenDepositAndSwap(_swap);
        _hyphenStart(_bridgeData);
    }

    function _hyphenStart(BridgeData memory _bridgeData) internal {
        bool isNotNative = !LibPlexusUtil._isNative(_bridgeData.srcToken);

        if (isNotNative) {
            IERC20(_bridgeData.srcToken).safeApprove(address(HYPHEN), _bridgeData.amount);
            HYPHEN.depositErc20(_bridgeData.dstChainId, _bridgeData.srcToken, _bridgeData.recipient, _bridgeData.amount, "PLEXUS");
            IERC20(_bridgeData.srcToken).safeApprove(address(HYPHEN), 0);
        } else {
            HYPHEN.depositNative{value: _bridgeData.amount}(_bridgeData.recipient, _bridgeData.dstChainId, "PLEXUS");
        }

        emit LibData.Bridge(_bridgeData.recipient, _bridgeData.dstChainId, _bridgeData.srcToken, _bridgeData.amount, _bridgeData.plexusData);
    }
}

