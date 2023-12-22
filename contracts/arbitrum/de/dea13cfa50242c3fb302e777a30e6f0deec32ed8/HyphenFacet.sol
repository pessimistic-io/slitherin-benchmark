pragma solidity 0.8.17;

import "./LibDiamond.sol";
import "./LibData.sol";
import "./LibPlexusUtil.sol";
import "./SafeERC20.sol";
import "./IHyphen.sol";
import "./ReentrancyGuard.sol";
import "./Signers.sol";
import "./VerifySigEIP712.sol";

contract HyphenFacet is ReentrancyGuard, Signers, VerifySigEIP712 {
    using SafeERC20 for IERC20;
    IHyphen private immutable HYPHEN;

    constructor(IHyphen _hyphen) {
        HYPHEN = _hyphen;
    }

    function bridgeToHyphen(HyphenDescription memory hDesc) external payable nonReentrant {
        LibPlexusUtil._isTokenDeposit(hDesc.token, hDesc.amount);
        hDesc.amount = LibPlexusUtil._fee(hDesc.token, hDesc.amount);
        _hyphenStart(hDesc);
    }

    function swapAndBridgeToHyphen(SwapData calldata _swap, HyphenDescription memory hDesc) external payable nonReentrant {
        hDesc.amount = LibPlexusUtil._fee(hDesc.token, LibPlexusUtil._tokenDepositAndSwap(_swap));
        _hyphenStart(hDesc);
    }

    function _hyphenStart(HyphenDescription memory hDesc) internal {
        bool isNotNative = !LibPlexusUtil._isNative(hDesc.token);

        if (isNotNative) {
            IERC20(hDesc.token).safeApprove(address(HYPHEN), hDesc.amount);
            HYPHEN.depositErc20(hDesc.toChainId, hDesc.token, hDesc.receiver, hDesc.amount, "PLEXUS");
        } else {
            HYPHEN.depositNative{value: hDesc.amount}(hDesc.receiver, hDesc.toChainId, "PLEXUS");
        }

        bytes32 transferId = keccak256(
            abi.encodePacked(address(this), hDesc.receiver, hDesc.token, hDesc.amount, hDesc.toChainId, hDesc.nonce, block.chainid)
        );

        emit LibData.Bridge(hDesc.receiver, uint64(hDesc.toChainId), hDesc.token, hDesc.toDstToken, hDesc.amount, transferId, "Hyphen");
    }
}

