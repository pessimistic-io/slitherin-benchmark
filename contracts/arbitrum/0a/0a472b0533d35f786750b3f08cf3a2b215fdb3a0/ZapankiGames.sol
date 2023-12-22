// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";
import "./AggregatorV3Interface.sol";
import "./ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import "./ChainSpecificUtil.sol";

interface IBankRoll {
    function getIsGame(address game) external view returns (bool);

    function getIsValidWager(address game, address tokenAddress) external view returns (bool);

    function transferPayout(address player, uint256 payout, address token) external;

    function getOwner() external view returns (address);

    function isPlayerSuspended(address player) external view returns (bool, uint256);
}

interface IVRFCoordinatorV2 is VRFCoordinatorV2Interface {
    function getFeeConfig()
        external
        view
        returns (uint32, uint32, uint32, uint32, uint32, uint24, uint24, uint24, uint24);
}

abstract contract ZapankiGames is ReentrancyGuard, VRFConsumerBaseV2 {
    using SafeERC20 for IERC20;

    uint256 public VRFFees;

    AggregatorV3Interface public LINK_ETH_FEED;
    IVRFCoordinatorV2 public vrfCoordinator;
    IBankRoll public bankroll;

    error NotApprovedBankroll();
    error InvalidValue(uint256 required, uint256 sent);
    error TransferFailed();
    error RefundFailed();
    error NotOwner(address want, address have);
    error ZeroWager();
    error PlayerSuspended(uint256 suspensionTime);

    constructor(address _vrfCoordinator) VRFConsumerBaseV2(_vrfCoordinator) {}

    /**
     * @dev function to transfer the player wager to bankroll, and charge for VRF fee
     * , reverts if bankroll doesn't approve game or token
     * @param tokenAddress address of the token the wager is made on
     * @param wager total amount wagered
     */

    function _transferWager(
        address tokenAddress,
        uint256 wager,
        uint256 gasAmount,
        uint256 l1Multiplier
    ) internal returns (uint256 VRFfee) {
        if (!bankroll.getIsValidWager(address(this), tokenAddress)) {
            revert NotApprovedBankroll();
        }
        if (wager == 0) {
            revert ZeroWager();
        }
        (bool suspended, uint256 suspendedTime) = bankroll.isPlayerSuspended(msg.sender);
        if (suspended) {
            revert PlayerSuspended(suspendedTime);
        }
        VRFfee = getVRFFee(gasAmount, l1Multiplier);

        if (tokenAddress == address(0)) {
            if (msg.value < wager + VRFfee) {
                revert InvalidValue(wager + VRFfee, msg.value);
            }
            _refundExcessValue(msg.value - (VRFfee + wager));
        } else {
            if (msg.value < VRFfee) {
                revert InvalidValue(VRFfee, msg.value);
            }

            IERC20(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                wager
            );

            _refundExcessValue(msg.value - VRFfee);
        }
        VRFFees += VRFfee;
    }

    /**
     * @dev function to transfer the wager held by the game contract to the bankroll
     * @param tokenAddress address of the token to transfer
     * @param amount token amount to transfer
     */
    function _transferToBankroll(address tokenAddress, uint256 amount) internal {
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(address(bankroll)).call{value: amount}("");
            if (!success) {
                revert RefundFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(address(bankroll), amount);
        }
    }

    /**
     * @dev calculates in form of native token the fee charged by chainlink VRF
     * @return fee amount of fee user has to pay
     */
    function getVRFFee(
        uint256 gasAmount,
        uint256 l1Multiplier
    ) public view returns (uint256 fee) {
        (, int256 answer, , , ) = LINK_ETH_FEED.latestRoundData();
        (uint32 fulfillmentFlatFeeLinkPPMTier1, , , , , , , , ) = vrfCoordinator
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
     * @dev returns to user the excess fee sent to pay for the VRF
     * @param refund amount to send back to user
     */
    function _refundExcessValue(uint256 refund) internal {
        if (refund == 0) {
            return;
        }
        (bool success, ) = payable(msg.sender).call{value: refund}("");
        if (!success) {
            revert RefundFailed();
        }
    }

    /**
     * @dev function to charge user for VRF
     */
    function _payVRFFee(
        uint256 gasAmount,
        uint256 l1Multiplier
    ) internal returns (uint256 VRFfee) {
        VRFfee = getVRFFee(gasAmount, l1Multiplier);
        if (msg.value < VRFfee) {
            revert InvalidValue(VRFfee, msg.value);
        }
        _refundExcessValue(msg.value - VRFfee);
        VRFFees += VRFfee;
    }

    /**
     * @dev function to transfer VRF fees acumulated in the contract to the bankroll
     * Can only be called by owner
     */
    function transferFees(address to) external nonReentrant {
        if (msg.sender != bankroll.getOwner()) {
            revert NotOwner(bankroll.getOwner(), msg.sender);
        }
        uint256 fee = VRFFees;
        VRFFees = 0;
        (bool success, ) = payable(address(to)).call{value: fee}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    /**
     * @dev function to transfer wager to game contract, without charging for VRF
     * @param tokenAddress tokenAddress the wager is made on
     * @param wager wager amount
     */
    function _transferWagerPvPNoVRF(address tokenAddress, uint256 wager) internal {
        if (!bankroll.getIsValidWager(address(this), tokenAddress)) {
            revert NotApprovedBankroll();
        }
        if (tokenAddress == address(0)) {
            if (!(msg.value == wager)) {
                revert InvalidValue(wager, msg.value);
            }
        } else {
            IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), wager);
        }
    }

    /**
     * @dev function to transfer wager to game contract, including charge for VRF
     * @param tokenAddress tokenAddress the wager is made on
     * @param wager wager amount
     */
    function _transferWagerPvP(address tokenAddress, uint256 wager, uint256 gasAmount) internal {
        if (!bankroll.getIsValidWager(address(this), tokenAddress)) {
            revert NotApprovedBankroll();
        }

        uint256 VRFfee = getVRFFee(gasAmount, 20);
        if (tokenAddress == address(0)) {
            if (msg.value < wager + VRFfee) {
                revert InvalidValue(wager, msg.value);
            }

            _refundExcessValue(msg.value - (VRFfee + wager));
        } else {
            if (msg.value < VRFfee) {
                revert InvalidValue(VRFfee, msg.value);
            }

            IERC20(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                wager
            );
            _refundExcessValue(msg.value - VRFfee);
        }
        VRFFees += VRFfee;
    }

    /**
     * @dev transfers payout from the game contract to the players
     * @param player address of the player to transfer the payout to
     * @param payout amount of payout to transfer
     * @param tokenAddress address of the token that payout will be transfered
     */
    function _transferPayoutPvP(address player, uint256 payout, address tokenAddress) internal {
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(player).call{value: payout}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(player, payout);
        }
    }

    /**
     * @dev transfers house edge from game contract to bankroll
     * @param amount amount to transfer
     * @param tokenAddress address of token to transfer
     */
    function _transferHouseEdgePvP(uint256 amount, address tokenAddress) internal {
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(address(bankroll)).call{value: amount}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(address(bankroll), amount);
        }
    }

    /**
     * @dev function to request bankroll to give payout to player
     * @param player address of the player
     * @param payout amount of payout to give
     * @param tokenAddress address of the token in which to give the payout
     */
    function _transferPayout(address player, uint256 payout, address tokenAddress) internal {
        bankroll.transferPayout(player, payout, tokenAddress);
    }

    /**
     * @dev function to send the request for randomness to chainlink
     * @param numWords number of random numbers required
     */
    function _requestRandomWords(uint32 numWords) internal returns (uint256 s_requestId) {
        s_requestId = vrfCoordinator.requestRandomWords(
            0x08ba8f62ff6c40a58877a106147661db43bc58dabfb814793847a839aa03367f,
            81,
            1,
            2500000,
            numWords
        );
    }
}

