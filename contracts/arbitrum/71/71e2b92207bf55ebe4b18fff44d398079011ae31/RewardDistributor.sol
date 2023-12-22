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
import { ISwitchCollateralRouter } from "./ISwitchCollateralRouter.sol";

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
    address merkleAirdrop,
    address switchCollateralRouter
  );
  event LogSetReferralRevenueMaxThreshold(uint256 oldThreshold, uint256 newThreshold);
  event LogSetTokenSwapPath(address[] token, address[][] path);

  /**
   * Errors
   */
  error RewardDistributor_NotFeeder();
  error RewardDistributor_BadParams();
  error RewardDistributor_InvalidArray();
  error RewardDistributor_InvalidSwapFee();
  error RewardDistributor_ReferralRevenueExceedMaxThreshold();
  error RewardDistributor_BadReferralRevenueMaxThreshold();
  error RewardDistributor_UnevenTokenSwapPath();

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

  // For SwitchCollateral
  mapping(address token => address[] path) public tokenSwapPath;
  ISwitchCollateralRouter public switchCollateralRouter;

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
    address _rewardToken,
    address _vaultStorage,
    address _poolRouter,
    address _sglp,
    IGmxRewardRouterV2 _rewardRouter,
    address _hlpStakingProtocolRevenueRewarder,
    address _hmxStakingProtocolRevenueRewarder,
    uint256 _hlpStakingBps,
    MerkleAirdrop _merkleAirdrop,
    uint256 _referralRevenueMaxThreshold,
    ISwitchCollateralRouter _switchCollateralRouter
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();

    rewardToken = _rewardToken;
    vaultStorage = _vaultStorage;
    sglp = _sglp;
    poolRouter = _poolRouter;
    rewardRouter = _rewardRouter;
    switchCollateralRouter = _switchCollateralRouter;
    hlpStakingProtocolRevenueRewarder = _hlpStakingProtocolRevenueRewarder;
    hmxStakingProtocolRevenueRewarder = _hmxStakingProtocolRevenueRewarder;
    hlpStakingBps = _hlpStakingBps;
    merkleAirdrop = _merkleAirdrop;

    referralRevenueMaxThreshold = _referralRevenueMaxThreshold;
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

    // Use SwitchCollateralRouter for every swap
    IERC20Upgradeable(token).safeTransfer(address(switchCollateralRouter), amount);
    switchCollateralRouter.execute(amount, tokenSwapPath[token]);
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
    address _rewardToken,
    address _vaultStorage,
    address _poolRouter,
    address _sglp,
    IGmxRewardRouterV2 _rewardRouter,
    address _hlpStakingProtocolRevenueRewarder,
    address _hmxStakingProtocolRevenueRewarder,
    uint256 _hlpStakingBps,
    MerkleAirdrop _merkleAirdrop,
    ISwitchCollateralRouter _switchCollateralRouter
  ) external onlyOwner {
    if (_hlpStakingBps > BPS) revert RewardDistributor_BadParams();

    rewardToken = _rewardToken;
    vaultStorage = _vaultStorage;
    sglp = _sglp;
    poolRouter = _poolRouter;
    rewardRouter = _rewardRouter;
    hlpStakingProtocolRevenueRewarder = _hlpStakingProtocolRevenueRewarder;
    hmxStakingProtocolRevenueRewarder = _hmxStakingProtocolRevenueRewarder;
    hlpStakingBps = _hlpStakingBps;
    merkleAirdrop = _merkleAirdrop;
    switchCollateralRouter = _switchCollateralRouter;

    emit LogSetParams(
      _rewardToken,
      _vaultStorage,
      _poolRouter,
      address(_rewardRouter),
      _hlpStakingProtocolRevenueRewarder,
      _hmxStakingProtocolRevenueRewarder,
      _hlpStakingBps,
      address(_merkleAirdrop),
      address(_switchCollateralRouter)
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

  function setTokenSwapPath(address[] calldata token, address[][] calldata path) external onlyOwner {
    if (token.length != path.length){
      revert RewardDistributor_UnevenTokenSwapPath();
    }
    emit LogSetTokenSwapPath(token, path);
    for (uint8 i; i < token.length; i++) {
      tokenSwapPath[token[i]] = path[i];
    }
  }
}

