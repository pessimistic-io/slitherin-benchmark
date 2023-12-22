// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Interfaces.sol";
import "./ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import "./ChainSpecificUtil.sol";

contract Common is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public VRFFees;
    address public ChainLinkVRF;
    AggregatorV3Interface public LINK_ETH_FEED;
    VRFCoordinatorV2Interface public IChainLinkVRF;
    IBankRollFacet public Bankroll;
    uint64 chainlinkSubId;
    bytes32 chainlinkKeyHash;

    /**
     * @dev Internal function to transfer the player's wager to the bankroll, and calculate the VRF fee.
     * @param tokenAddress Address of the token the wager is made on.
     * @param wager Total amount wagered.
     * @param msgSender Address of the message sender.
     */
    function _transferWager(
        address tokenAddress,
        uint256 wager,
        address msgSender,
        uint256 VRFfee
    ) internal {
        if (tokenAddress == address(0)) {
            require(
                msg.value >= wager + VRFfee,
                "msg.value must be greater than or equal to wager + VRFfee"
            );
            _refundExcessValue(msg.value - (VRFfee + wager), msgSender);
        } else {
            require(
                msg.value >= VRFfee,
                "msg.value must be greater than or equal to VRFfee"
            );
            _refundExcessValue(msg.value - VRFfee, msgSender);
        }
        VRFFees += VRFfee;
    }

    /**
     * @dev Internal function to transfer the wager held by the game contract to the bankroll.
     * @param tokenAddress Address of the token to transfer.
     * @param amount Token amount to transfer.
     */
    function _transferToBankroll(
        address tokenAddress,
        uint256 amount
    ) internal {
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(address(Bankroll)).call{value: amount}(
                ""
            );
            require(success, "Refund failed");
        } else {
            IERC20(tokenAddress).safeTransfer(address(Bankroll), amount);
        }
    }

    /**
     * @dev Internal function to calculate the VRF fee based on gas costs and Chainlink price feed.
     * @param gasAmount Gas amount for the transaction.
     * @param l1Multiplier Multiplier for L1 gas fees.
     * @return fee The calculated VRF fee.
     */
    function getVRFFee(
        uint256 gasAmount,
        uint256 l1Multiplier
    ) public view returns (uint256 fee) {
        (, int256 answer, , , ) = LINK_ETH_FEED.latestRoundData();
        (uint32 fulfillmentFlatFeeLinkPPMTier1, , , , , , , , ) = IChainLinkVRF
            .getFeeConfig();

        uint256 l1CostWei = (ChainSpecificUtil.getCurrentTxL1GasFees() *
            l1Multiplier) / 10;
        fee =
            tx.gasprice *
            (gasAmount) +
            l1CostWei +
            ((1e12 *
                uint256(fulfillmentFlatFeeLinkPPMTier1) *
                uint256(answer)) / 1e18);
    }

    /**
     * @dev Internal function to refund any excess value sent with the transaction.
     * @param refund Amount to send back to the user.
     * @param msgSender Address of the message sender.
     */
    function _refundExcessValue(uint256 refund, address msgSender) internal {
        if (refund == 0) {
            return;
        }
        (bool success, ) = payable(msgSender).call{value: refund}("");
        require(success, "Refund failed");
    }

    /**
     * @dev Function to transfer VRF fees accumulated in the contract to the Bankroll.
     * Can only be called by the owner.
     * @param to Address to which the fees should be transferred.
     */
    function transferFees(address to) external {
        require(msg.sender == Bankroll.getOwner(), "Not owner");
        uint256 fee = VRFFees;
        VRFFees = 0;
        (bool success, ) = payable(address(to)).call{value: fee}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Internal function to request the bankroll to give a payout to the player.
     * @param player Address of the player.
     * @param payout Amount of payout to give.
     * @param tokenAddress Address of the token in which to give the payout.
     */
    function _transferPayout(
        address player,
        uint256 payout,
        address tokenAddress
    ) internal {
        Bankroll.transferPayout(player, payout, tokenAddress);
    }

    /**
     * @dev Internal function to send the request for randomness to Chainlink.
     * @param numWords Number of random numbers required.
     * @return s_requestId The Chainlink request ID.
     */
    function _requestRandomWords(
        uint32 numWords
    ) internal returns (uint256 s_requestId) {
        s_requestId = VRFCoordinatorV2Interface(ChainLinkVRF)
            .requestRandomWords(
                chainlinkKeyHash,
                chainlinkSubId,
                1,
                2500000,
                numWords
            );
    }
}

