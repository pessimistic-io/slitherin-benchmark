// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ICBridge.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./PbPool.sol";
import "./Signers.sol";
import "./LibData.sol";
import "./LibPlexusUtil.sol";
import "./VerifySigEIP712.sol";
import "./console.sol";

contract CBridgeFacet is ReentrancyGuard, Signers, VerifySigEIP712 {
    using SafeERC20 for IERC20;

    ICBridge private immutable CBRIDGE;
    address private immutable WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor(ICBridge cbridge) {
        CBRIDGE = cbridge;
    }

    /**
    @notice bridge via Cbridge logic
    @param bDesc Data specific to cBridge
    */
    function bridgeToCbridge(CBridgeDescription memory bDesc) external payable nonReentrant {
        LibPlexusUtil._isTokenDeposit(bDesc.srcToken, bDesc.amount);
        bDesc.amount = LibPlexusUtil._fee(bDesc.srcToken, bDesc.amount);
        _cBridgeStart(bDesc);
    }

    /**
    @notice swap And bridge via Cbridge logic
    @param _swap Data specific to Swap
    @param bDesc Data specific to cBridge
    */
    function swapAndBridgeToCbridge(SwapData calldata _swap, CBridgeDescription memory bDesc) external payable nonReentrant {
        bDesc.amount = LibPlexusUtil._fee(bDesc.srcToken, LibPlexusUtil._tokenDepositAndSwap(_swap));
        _cBridgeStart(bDesc);
    }

    /** @notice Refunds due to errors during cBridge transfer */
    function sigWithdraw(bytes calldata _wdmsg, bytes[] calldata _sigs, address[] calldata _signers, uint256[] calldata _powers) external {
        LibData.BridgeData storage ds = LibData.bridgeStorage();
        CBRIDGE.withdraw(_wdmsg, _sigs, _signers, _powers);
        bytes32 domain = keccak256(abi.encodePacked(block.chainid, CBRIDGE, "WithdrawMsg"));
        verifySigs(abi.encodePacked(domain, _wdmsg), _sigs, _signers, _powers);
        PbPool.WithdrawMsg memory wdmsg = PbPool.decWithdrawMsg(_wdmsg);
        BridgeInfo memory tif = ds.transferInfo[wdmsg.refid];

        bool isNotNative = !LibPlexusUtil._isNative(tif.dstToken);
        if (isNotNative) {
            IERC20(tif.dstToken).safeTransfer(tif.user, tif.amount);
        } else {
            LibPlexusUtil._safeNativeTransfer(tif.user, tif.amount);
        }
    }

    function viewInfo(bytes32 transferId) external view returns (BridgeInfo memory) {
        LibData.BridgeData storage ds = LibData.bridgeStorage();
        BridgeInfo memory tif = ds.transferInfo[transferId];
        return tif;
    }

    /**
    @notice Function to start cBridge
    @param bDesc Data specific to cBridge
    */
    function _cBridgeStart(CBridgeDescription memory bDesc) internal {
        bool isNotNative = !LibPlexusUtil._isNative(bDesc.srcToken);
        if (isNotNative) {
            IERC20(bDesc.srcToken).safeApprove(address(CBRIDGE), bDesc.amount);
            CBRIDGE.send(bDesc.receiver, bDesc.srcToken, bDesc.amount, bDesc.dstChainId, bDesc.nonce, bDesc.maxSlippage);
        } else {
            CBRIDGE.sendNative{value: bDesc.amount}(bDesc.receiver, bDesc.amount, bDesc.dstChainId, bDesc.nonce, bDesc.maxSlippage);
            bDesc.srcToken = WETH;
        }

        bytes32 transferId = keccak256(
            abi.encodePacked(address(this), bDesc.receiver, bDesc.srcToken, bDesc.amount, bDesc.dstChainId, bDesc.nonce, uint64(block.chainid))
        );
        LibData.BridgeData storage ds = LibData.bridgeStorage();
        BridgeInfo memory tif = ds.transferInfo[transferId];
        tif.dstToken = bDesc.srcToken;
        tif.chainId = bDesc.dstChainId;
        tif.amount = bDesc.amount;
        tif.user = msg.sender;
        tif.bridge = "CBridge";
        ds.transferInfo[transferId] = tif;

        emit LibData.Bridge(msg.sender, bDesc.dstChainId, bDesc.srcToken, bDesc.toDstToken, bDesc.amount, transferId, "CBridge");
    }
}

