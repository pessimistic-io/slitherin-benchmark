// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";
import "./AggregatorV3Interface.sol";
import "./ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import "./IVRFCoordinator.sol";
import "./IBankroll.sol";
import "./ChainSpecificUtil.sol";

abstract contract ZapankiGamesL2 is ReentrancyGuard, VRFConsumerBaseV2 {
    using SafeERC20 for IERC20;

    AggregatorV3Interface public LINK_ETH_FEED;
    IVRFCoordinatorV2 public vrfCoordinator;
    IBankroll public bankroll;
    address public trustedForwarder;

    bytes32 vrfKeyHash;
    uint256 public claimableVRFFee;
    uint64 constant BLOCK_REFUND_COOLDOWN = 1000;
    uint64 vrfSubId;
    uint32 vrfCallbackGasLimit;

    modifier onlyOwner() {
        require(msg.sender == bankroll.owner(), "Not Owner");
        _;
    }

    constructor(
        address _vrfCoordinator,
        IBankroll _bankroll,
        address _trustedForwarder,
        address _link_eth_feed,
        bytes32 _vrfKeyHash,
        uint64 _vrfSubId,
        uint32 _vrfCallbackGasLimit
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        vrfCoordinator = IVRFCoordinatorV2(_vrfCoordinator);
        bankroll = _bankroll;
        LINK_ETH_FEED = AggregatorV3Interface(_link_eth_feed);
        vrfKeyHash = _vrfKeyHash;
        vrfSubId = _vrfSubId;
        vrfCallbackGasLimit = _vrfCallbackGasLimit;
        trustedForwarder = _trustedForwarder;
    }

    function isTrustedForwarder(address forwarder) public view virtual returns (bool) {
        return forwarder == trustedForwarder;
    }

    function _msgSender() internal view returns (address sender) {
        if (isTrustedForwarder(msg.sender)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            /// @solidity memory-safe-assembly
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return msg.sender;
        }
    }

    function _shouldStop(int256 value, uint256 stopGain, uint256 stopLoss) internal pure returns (bool) {
        return value >= int256(stopGain) || value <= -int256(stopLoss);
    }

    function _processWager(
        address tokenAddress,
        uint256 wager,
        uint256 gasAmount,
        uint256 l1Multiplier,
        address msgSender
    ) internal {
        require(bankroll.getIsValidWager(address(this), tokenAddress), "Token not approved");
        require(wager != 0, "Wager must be greater than 0");
        if (tokenAddress == address(0)) {
            _chargeVRFFee(msg.value - wager, gasAmount, l1Multiplier);
        } else {
            _chargeVRFFee(msg.value, gasAmount, l1Multiplier);
            IERC20(tokenAddress).safeTransferFrom(msgSender, address(this), wager);
        }
    }

    function _transferToBankroll(address tokenAddress, uint256 amount) internal {
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(address(bankroll)).call{value: amount}("");
            require(success, "refund failed");
        } else {
            IERC20(tokenAddress).safeTransfer(address(bankroll), amount);
        }
    }

    function getVRFFee(uint256 gasAmount, uint256 l1Multiplier) public view returns (uint256 fee) {
        (, int256 answer, , , ) = LINK_ETH_FEED.latestRoundData();
        (uint32 fulfillmentFlatFeeLinkPPMTier1, , , , , , , , ) = vrfCoordinator.getFeeConfig();
        fee =
            tx.gasprice *
            (gasAmount) +
            ((ChainSpecificUtil.getCurrentTxL1GasFees() * l1Multiplier) / 10) +
            ((1e12 * uint256(fulfillmentFlatFeeLinkPPMTier1) * uint256(answer)) / 1e18);
    }

    function _refundVRFFee(uint256 refundableAmount) internal {
        if (refundableAmount > 0) {
            (bool success, ) = payable(msg.sender).call{value: refundableAmount}("");
            require(success, "refund failed");
        }
    }

    function _chargeVRFFee(uint256 vrfFeeProvided, uint256 gasAmount, uint256 l1Multiplier) internal {
        uint256 _vrfFee = getVRFFee(gasAmount, l1Multiplier);
        require(vrfFeeProvided >= _vrfFee, "Insufficient vrf fee");
        _refundVRFFee(vrfFeeProvided - _vrfFee);
        claimableVRFFee += _vrfFee;
    }

    function collectVrfFee() external nonReentrant onlyOwner {
        uint256 fee = claimableVRFFee;
        claimableVRFFee = 0;
        (bool success, ) = payable(address(msg.sender)).call{value: fee}("");
        require(success, "transfer failed");
    }

    function _payoutBankrollToPlayer(address player, uint256 payout, address tokenAddress) internal {
        bankroll.transferPayout(player, payout, tokenAddress);
    }

    function _requestRandomWords(uint32 numWords) internal returns (uint256 s_requestId) {
        s_requestId = vrfCoordinator.requestRandomWords(vrfKeyHash, vrfSubId, 3, vrfCallbackGasLimit, numWords);
    }
}

