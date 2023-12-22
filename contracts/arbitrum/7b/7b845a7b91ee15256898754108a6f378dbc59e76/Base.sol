// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

// imports chainlink
import "./VRFConsumerBaseV2.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./AggregatorV3Interface.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";

import "./console.sol";

import "./ChainSpecificUtil.sol";

import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface IBankroll {
  // Check if a wager is valid for a given game and token address
  function getIsValidWager(address game, address tokenAddress) external view returns (bool);

  // Check if a address is suspended
  function isAddressSuspended(address player) external view returns (bool, uint256);

  // Get the owner address of the Bankroll contract
  function owner() external view returns (address);

  // Transfer the payout amount in tokens from the Bankroll contract to the player
  function transferPayout(address player, uint256 payout, address token) external;

  // Check if a game contract address is authorized
  function isGameApproved(address gameAddress) external view returns (bool);

  function getStoppedStatus() external view returns (bool);
}

interface IVRFCoordinatorV2 is VRFCoordinatorV2Interface {
  function getFeeConfig()
    external
    view
    returns (uint32, uint32, uint32, uint32, uint32, uint24, uint24, uint24, uint24);
}

contract Base is ReentrancyGuard, Ownable {
  using SafeERC20 for IERC20;

  error NotApprovedBankroll();
  error InvalidValue(uint256 wagerPlusVRFfee, uint256 msgvalue);
  error AddressSuspended(uint256 suspendedTime);

  /** Chainlink Feed / Token */
  AggregatorV3Interface public linkPriceFeed;
  IVRFCoordinatorV2 public IChainLinkVRF;
  uint256 public VRFFees;

  IBankroll public Bankroll;

  event RefundSuccess(address indexed user, uint256 refund);
  event TransferToBankroll(address indexed player, uint256 amount);

  /**
   * @dev function to request bankroll to give payout to player
   * @param player address of the player
   * @param payout amount of payout to give
   * @param tokenAddress address of the token in which to give the payout
   */
  function _transferPayout(address player, uint256 payout, address tokenAddress) internal {
    Bankroll.transferPayout(player, payout, tokenAddress);
  }

  /**
   * @dev function to transfer the player wager to Bankroll, and charge for VRF fee
   * , reverts if Bankroll doesn't approve game or token
   * @param tokenAddress address of the token the wager is made on
   * @param wager total amount wagered
   */

  function _transferWager(
    address tokenAddress,
    uint256 wager,
    uint256 gasAmount,
    uint256 l1Multiplier
  ) internal returns (uint256 VRFfee) {
    if (!Bankroll.getIsValidWager(address(this), tokenAddress)) {
      revert NotApprovedBankroll();
    }
    require(wager != 0, "zero wager");
    (bool suspended, uint256 suspendedTime) = Bankroll.isAddressSuspended(msg.sender);
    if (suspended) {
      revert AddressSuspended(suspendedTime);
    }

    VRFfee = getVRFFee(gasAmount, l1Multiplier);

    if (tokenAddress == address(0)) {
      if (msg.value < wager + VRFfee) {
        revert InvalidValue(wager + VRFfee, msg.value);
      }
      _refundExcessValue(msg.value - (VRFfee + wager));
    } else {
      require(msg.value >= VRFfee, "Insufficient ETH provided for VRF fee");
      IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), wager);
      _refundExcessValue(msg.value - VRFfee);
    }
    VRFFees += VRFfee;
  }

  function _transferToBankroll(uint256 amount, address tokenAddress) internal nonReentrant {
    if (tokenAddress == address(0)) {
      (bool success, ) = payable(address(Bankroll)).call{value: amount}("");
      require(success, "Transfer  to BR Failed");
    } else {
      IERC20(tokenAddress).safeTransfer(address(Bankroll), amount);
    }
    emit TransferToBankroll(msg.sender, amount);
  }

  /**
   * @dev calculates in form of native token the fee charged by chainlink VRF
   * @return fee amount of fee user has to pay
   */

  function getVRFFee(uint256 gasAmount, uint256 l1Multiplier) public view returns (uint256 fee) {
    (, int256 answer, , , ) = linkPriceFeed.latestRoundData();
    (uint32 fulfillmentFlatFeeLinkPPMTier1, , , , , , , , ) = IChainLinkVRF.getFeeConfig();

    uint256 l1CostWei = (ChainSpecificUtil.getCurrentTxL1GasFees() * l1Multiplier) / 10;

    fee =
      tx.gasprice *
      (gasAmount) +
      l1CostWei +
      ((1e12 * uint256(fulfillmentFlatFeeLinkPPMTier1) * uint256(answer)) / 1e18);
  }

  /**
   * @dev function to transfer VRF fees acumulated in the contract to the Bankroll
   * Can only be called by owner
   */
  function transferFees(address to) external nonReentrant onlyOwner {
    require(msg.sender == Bankroll.owner(), "NotOwner");
    uint256 fee = VRFFees;
    VRFFees = 0;
    (bool success, ) = payable(to).call{value: fee}("");
    require(success, " TransferFailed");
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
    require(success, "refund failed");
    emit RefundSuccess(msg.sender, refund);
  }

  function setBankroll(IBankroll _bankroll) external onlyOwner {
    Bankroll = _bankroll;
  }

  /**
   * @dev function to charge user for VRF
   */
  function _payVRFFee(uint256 gasAmount, uint256 l1Multiplier) internal returns (uint256 VRFfee) {
    VRFfee = getVRFFee(gasAmount, l1Multiplier);
    if (msg.value < VRFfee) {
      revert InvalidValue(VRFfee, msg.value);
    }
    _refundExcessValue(msg.value - VRFfee);
    VRFFees += VRFfee;
  }
}

