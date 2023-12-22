pragma solidity 0.8.17;

import "./LibDiamond.sol";
import "./LibData.sol";
import "./LibPlexusUtil.sol";
import "./SafeERC20.sol";
import "./IHop.sol";
import "./ReentrancyGuard.sol";

contract HopFacet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    function initHop(HopMapping[] calldata mappings) external {
        require(msg.sender == LibDiamond.contractOwner());
        LibData.HopData storage s = LibData.hopStorage();

        for (uint256 i; i < mappings.length; i++) {
            s.bridge[mappings[i].tokenAddress] = mappings[i].bridgeAddress;
            s.relayer[mappings[i].tokenAddress] = mappings[i].relayerAddress;
            s.allowedBridge[mappings[i].bridgeAddress] = true;
            s.allowedRelayer[mappings[i].relayerAddress] = true;
        }
    }

    function bridgeToHop(HopDescription memory hDesc) external payable nonReentrant {
        LibPlexusUtil._isTokenDeposit(hDesc.srcToken, hDesc.amount);
        hDesc.amount = LibPlexusUtil._fee(hDesc.srcToken, hDesc.amount);
        _hopStart(hDesc);
    }

    function swapAndBridgeToHop(SwapData calldata _swap, HopDescription memory hDesc) external payable nonReentrant {
        hDesc.amount = LibPlexusUtil._fee(hDesc.srcToken, LibPlexusUtil._tokenDepositAndSwap(_swap));
        _hopStart(hDesc);
    }

    function _hopStart(HopDescription memory hDesc) internal {
        bool isNotNative = !LibPlexusUtil._isNative(hDesc.srcToken);
        address bridge = hopBridge(hDesc.srcToken);
        require(hopBridgeAllowed(bridge) && hopRelayerAllowed(hopRelayer(hDesc.srcToken)));

        if (isNotNative) {
            if (IERC20(hDesc.srcToken).allowance(address(this), bridge) > 0) {
                IERC20(hDesc.srcToken).safeApprove(bridge, 0);
            }
            IERC20(hDesc.srcToken).safeIncreaseAllowance(bridge, hDesc.amount);
        }

        if (block.chainid == 1) {
            IHop(bridge).sendToL2{value: isNotNative ? 0 : hDesc.amount}(
                hDesc.dstChainId,
                hDesc.recipient,
                hDesc.amount,
                getSlippage(hDesc.amount, hDesc.slippage),
                hDesc.deadline,
                hopRelayer(hDesc.srcToken),
                hDesc.bonderFee
            );
        } else {
            IHop(bridge).swapAndSend{value: isNotNative ? 0 : hDesc.amount}(
                hDesc.dstChainId,
                hDesc.recipient,
                hDesc.amount,
                hDesc.bonderFee,
                getSlippage(hDesc.amount, hDesc.slippage),
                hDesc.deadline,
                hDesc.dstAmountOutMin,
                hDesc.dstDeadline
            );
        }

        bytes32 transferId = keccak256(
            abi.encodePacked(address(this), hDesc.recipient, hDesc.srcToken, hDesc.amount, hDesc.dstChainId, block.timestamp, uint64(block.chainid))
        );

        emit LibData.Bridge(hDesc.recipient, uint64(hDesc.dstChainId), hDesc.srcToken, hDesc.toDstToken, hDesc.amount, transferId, "Hop");
    }

    function hopBridge(address token) private view returns (address) {
        LibData.HopData storage s = LibData.hopStorage();
        address bridge = s.bridge[token];
        if (bridge == address(0)) revert();
        return bridge;
    }

    function hopRelayer(address token) private view returns (address) {
        LibData.HopData storage s = LibData.hopStorage();
        address relayer = s.relayer[token];
        if (relayer == address(0)) revert();
        return relayer;
    }

    function hopRelayerAllowed(address relayer) private view returns (bool) {
        LibData.HopData storage s = LibData.hopStorage();
        bool allowed = s.allowedRelayer[relayer];
        return allowed;
    }

    function hopBridgeAllowed(address bridge) private view returns (bool) {
        LibData.HopData storage s = LibData.hopStorage();
        bool allowed = s.allowedBridge[bridge];
        return allowed;
    }

    // percent
    function getSlippage(uint256 amount, uint256 percent) private view returns (uint256) {
        uint256 amountOutMin = amount - ((amount * percent) / 1000);
    }
}

