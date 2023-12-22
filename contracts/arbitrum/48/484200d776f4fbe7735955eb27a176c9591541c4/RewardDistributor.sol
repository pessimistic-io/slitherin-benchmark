// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.
pragma solidity 0.8.18;

import { IERC20Upgradeable } from "./ERC20_IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

import { MerkleAirdrop } from "./MerkleAirdrop.sol";

// Interfaces
import { IVaultStorage } from "./IVaultStorage.sol";
import { IUniswapV3Router } from "./IUniswapV3Router.sol";
import { IRewarder } from "./IRewarder.sol";
import { IGmxRewardRouterV2 } from "./IGmxRewardRouterV2.sol";

contract RewardDistributor is OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  /**
   * Events
   */
  event LogSetFeeder(address oldValue, address newValue);
  event LogSetUniV3SwapFee(uint24 oldValue, uint24 newValue);
  event LogProtocolFee(uint256 weekTimestamp, uint256 stakingAmount);
  event LogSetUniFeeBps(address[] rewardTokens, address[] swapTokens, uint24[] uniV3FeeBps);
  event LogSetParams(
    address rewardToken,
    address vaultStorage,
    address poolRouter,
    address rewardRouter,
    address hlpStakingProtocolRevenueRewarder,
    address hmxStakingProtocolRevenueRewarder,
    uint256 plpStakingBps,
    address merkleAirdrop
  );
  event LogSetReferralRevenueMaxThreshold(uint256 oldThreshold, uint256 newThreshold);

  /**
   * Errors
   */
  error RewardDistributor_NotFeeder();
  error RewardDistributor_BadParams();
  error RewardDistributor_InvalidArray();
  error RewardDistributor_InvalidSwapFee();
  error RewardDistributor_ReferralRevenueExceedMaxThreshold();
  error RewardDistributor_BadReferralRevenueMaxThreshold();

  /**
   * States
   */

  uint256 public constant BPS = 10000;

  /// @dev Token addreses
  address public rewardToken; // the token to be fed to rewarder
  address public sglp;

  /// @dev Pool and its companion addresses
  address public poolRouter;
  address public hlpStakingProtocolRevenueRewarder;

  address public vaultStorage;
  address public feeder;
  MerkleAirdrop public merkleAirdrop;
  IGmxRewardRouterV2 public rewardRouter;

  /// @dev Distribution weights
  uint256 public hlpStakingBps;

  // rewardToken => swapToken => feeBps
  mapping(address => mapping(address => uint24)) public uniswapV3SwapFeeBPSs;

  address public hmxStakingProtocolRevenueRewarder;

  uint256 public referralRevenueMaxThreshold; // in BPS (10000)

  /**
   * Modifiers
   */
  modifier onlyFeeder() {
    if (msg.sender != feeder) revert RewardDistributor_NotFeeder();
    _;
  }

  /**
   * Initialize
   */

  function initialize(
    address rewardToken_,
    address vaultStorage_,
    address poolRouter_,
    address sglp_,
    IGmxRewardRouterV2 rewardRouter_,
    address hlpStakingProtocolRevenueRewarder_,
    address hmxStakingProtocolRevenueRewarder_,
    uint256 hlpStakingBps_,
    MerkleAirdrop merkleAirdrop_,
    uint256 referralRevenueMaxThreshold_
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();

    rewardToken = rewardToken_;
    vaultStorage = vaultStorage_;
    sglp = sglp_;
    poolRouter = poolRouter_;
    rewardRouter = rewardRouter_;
    hlpStakingProtocolRevenueRewarder = hlpStakingProtocolRevenueRewarder_;
    hmxStakingProtocolRevenueRewarder = hmxStakingProtocolRevenueRewarder_;
    hlpStakingBps = hlpStakingBps_;
    merkleAirdrop = merkleAirdrop_;

    referralRevenueMaxThreshold = referralRevenueMaxThreshold_;
  }

  /**
   * Core Functions
   */

  function claimAndSwap(address[] memory tokens) external onlyFeeder {
    _claimAndSwap(tokens);
  }

  function feedProtocolRevenue(
    uint256 feedingExpiredAt,
    uint256 weekTimestamp,
    uint256 referralRevenueAmount,
    bytes32 merkleRoot
  ) external onlyFeeder {
    _feedProtocolRevenue(feedingExpiredAt, weekTimestamp, referralRevenueAmount, merkleRoot);
  }

  function claimAndFeedProtocolRevenue(
    address[] memory tokens,
    uint256 feedingExpiredAt,
    uint256 weekTimestamp,
    uint256 referralRevenueAmount,
    bytes32 merkleRoot
  ) external onlyFeeder {
    _claimAndSwap(tokens);
    _feedProtocolRevenue(feedingExpiredAt, weekTimestamp, referralRevenueAmount, merkleRoot);
  }

  /**
   * Internal Functions
   */

  function _claimAndSwap(address[] memory tokens) internal {
    uint256 length = tokens.length;
    for (uint256 i = 0; i < length; ) {
      if (IVaultStorage(vaultStorage).protocolFees(tokens[i]) > 0) {
        // 1. Withdraw protocol revenue
        _withdrawProtocolRevenue(tokens[i]);

        // 2. Swap those revenue (along with surplus) to RewardToken Token
        _swapTokenToRewardToken(tokens[i], IERC20Upgradeable(tokens[i]).balanceOf(address(this)));
      }

      unchecked {
        i++;
      }
    }
  }

  function _withdrawProtocolRevenue(address _token) internal {
    // Withdraw the all max amount revenue from the pool
    IVaultStorage(vaultStorage).withdrawFee(
      _token,
      IVaultStorage(vaultStorage).protocolFees(_token),
      address(this)
    );
  }

  function _swapTokenToRewardToken(address token, uint256 amount) internal {
    // If no token, no need to swap
    if (amount == 0) return;

    // If token is already reward token, no need to swap
    if (token == rewardToken) return;

    if (token == sglp) {
      rewardRouter.unstakeAndRedeemGlp(rewardToken, amount, 0, address(this));
      return;
    }

    // Approve the token
    IERC20Upgradeable(token).approve(poolRouter, amount);

    uint24 uniswapV3SwapFeeBPS = uniswapV3SwapFeeBPSs[rewardToken][token];
    if (uniswapV3SwapFeeBPS == 0) revert RewardDistributor_InvalidSwapFee();

    // Swap at Uni-V3
    IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
      .ExactInputSingleParams({
        tokenIn: token,
        tokenOut: rewardToken,
        fee: uniswapV3SwapFeeBPS,
        recipient: address(this),
        deadline: block.timestamp,
        amountIn: amount,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      });

    IUniswapV3Router(poolRouter).exactInputSingle(params);
  }

  function _feedProtocolRevenue(
    uint256 feedingExpiredAt,
    uint256 weekTimestamp,
    uint256 referralRevenueAmount,
    bytes32 merkleRoot
  ) internal {
    // Transfer referral revenue to merkle airdrop address for distribution
    uint256 totalProtocolRevenue = IERC20Upgradeable(rewardToken).balanceOf(address(this));

    // totalProtocolRevenue * referralRevenueMaxThreshold / 10000 < referralRevenueAmount
    if (totalProtocolRevenue * referralRevenueMaxThreshold < referralRevenueAmount * 10000)
      revert RewardDistributor_ReferralRevenueExceedMaxThreshold();

    if (referralRevenueAmount > 0) {
      merkleAirdrop.init(weekTimestamp, merkleRoot);
      IERC20Upgradeable(rewardToken).safeTransfer(address(merkleAirdrop), referralRevenueAmount);
    }

    // At this point, we got a portion of reward tokens for protocol revenue.
    // Feed reward to both rewarders
    uint256 totalRewardAmount = _feedRewardToRewarders(feedingExpiredAt);

    emit LogProtocolFee(weekTimestamp, totalRewardAmount);
  }

  function _feedRewardToRewarders(uint256 feedingExpiredAt) internal returns (uint256) {
    uint256 totalRewardAmount = IERC20Upgradeable(rewardToken).balanceOf(address(this));
    uint256 hlpStakingRewardAmount = (totalRewardAmount * hlpStakingBps) / BPS;
    uint256 hmxStakingRewardAmount = totalRewardAmount - hlpStakingRewardAmount;

    // Approve and feed to HLPStaking
    IERC20Upgradeable(rewardToken).approve(
      hlpStakingProtocolRevenueRewarder,
      hlpStakingRewardAmount
    );
    IRewarder(hlpStakingProtocolRevenueRewarder).feedWithExpiredAt(
      hlpStakingRewardAmount,
      feedingExpiredAt
    );

    // Approve and feed to HMXStaking
    IERC20Upgradeable(rewardToken).approve(
      hmxStakingProtocolRevenueRewarder,
      hmxStakingRewardAmount
    );
    IRewarder(hmxStakingProtocolRevenueRewarder).feedWithExpiredAt(
      hmxStakingRewardAmount,
      feedingExpiredAt
    );

    return totalRewardAmount;
  }

  /**
   * Setter
   */

  function setFeeder(address newFeeder) external onlyOwner {
    emit LogSetFeeder(feeder, newFeeder);
    feeder = newFeeder;
  }

  function setUniFeeBps(
    address[] memory rewardTokens,
    address[] memory swapTokens,
    uint24[] memory uniV3FeeBpses
  ) external onlyOwner {
    if (rewardTokens.length != swapTokens.length || swapTokens.length != uniV3FeeBpses.length)
      revert RewardDistributor_InvalidArray();

    uint256 len = rewardTokens.length;
    for (uint256 i = 0; i < len; ) {
      uniswapV3SwapFeeBPSs[rewardTokens[i]][swapTokens[i]] = uniV3FeeBpses[i];

      unchecked {
        ++i;
      }
    }

    emit LogSetUniFeeBps(rewardTokens, swapTokens, uniV3FeeBpses);
  }

  function setParams(
    address rewardToken_,
    address vaultStorage_,
    address poolRouter_,
    IGmxRewardRouterV2 rewardRouter_,
    address sglp_,
    address hlpStakingProtocolRevenueRewarder_,
    address hmxStakingProtocolRevenueRewarder_,
    uint256 hlpStakingBps_,
    MerkleAirdrop merkleAirdrop_
  ) external onlyOwner {
    if (hlpStakingBps_ > BPS) revert RewardDistributor_BadParams();

    rewardToken = rewardToken_;
    vaultStorage = vaultStorage_;
    sglp = sglp_;
    poolRouter = poolRouter_;
    rewardRouter = rewardRouter_;
    hlpStakingProtocolRevenueRewarder = hlpStakingProtocolRevenueRewarder_;
    hmxStakingProtocolRevenueRewarder = hmxStakingProtocolRevenueRewarder_;
    hlpStakingBps = hlpStakingBps_;
    merkleAirdrop = merkleAirdrop_;

    emit LogSetParams(
      rewardToken_,
      vaultStorage_,
      poolRouter_,
      address(rewardRouter_),
      hlpStakingProtocolRevenueRewarder_,
      hmxStakingProtocolRevenueRewarder_,
      hlpStakingBps_,
      address(merkleAirdrop_)
    );
  }

  function setReferralRevenueMaxThreshold(
    uint256 newReferralRevenueMaxThreshold
  ) external onlyOwner {
    if (newReferralRevenueMaxThreshold > 5000) {
      // should not exceed 50% of total revenue
      revert RewardDistributor_BadReferralRevenueMaxThreshold();
    }
    emit LogSetReferralRevenueMaxThreshold(
      referralRevenueMaxThreshold,
      newReferralRevenueMaxThreshold
    );
    referralRevenueMaxThreshold = newReferralRevenueMaxThreshold;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}

