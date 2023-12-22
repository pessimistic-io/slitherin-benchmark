// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./ERC4626.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./IERC20Metadata.sol";

import "./ILendingPool.sol";
import "./ILockZap.sol";
import "./IMultiFeeDistribution.sol";
import "./IAToken.sol";
import "./IFeeDistribution.sol";
import "./AbstractVault.sol";

contract RadiantArbitrumVault is AbstractVault {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  event WithdrawFailed(address token);

  ILendingPool public immutable radiantLending;
  ILockZap public immutable lockZap;
  IMultiFeeDistribution public constant MULTIFEE_DISTRIBUTION =
    IMultiFeeDistribution(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);
  address[6] public radiantRewardNativeTokenAddresses = [
    0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, // wbtc
    0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, // usdt
    0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, // usdc.e
    0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1, // dai
    0x5979D7b546E38E414F7E9822514be443A4800529, // wsteth
    0x912CE59144191C1204E64559FE8253a0e49E6548 //  arb
  ];

  constructor(
    IERC20Metadata asset_,
    address radiantLending_
  ) ERC4626(asset_) ERC20("RadiantArbitrum-DLP", "ALP-ra-dlp") {
    radiantLending = ILendingPool(radiantLending_);
    lockZap = ILockZap(0x8991C4C347420E476F1cf09C03abA224A76E2997);
  }

  function totalLockedAssets() public view override returns (uint256) {
    // slither-disable-next-line unused-return
    (uint256 lockedBalances, , , , ) = IFeeDistribution(
      0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE
    ).lockedBalances(address(this));
    return lockedBalances;
  }

  function totalStakedButWithoutLockedAssets()
    public
    pure
    override
    returns (uint256)
  {
    return 0;
  }

  function totalUnstakedAssets() public view override returns (uint256) {
    return IERC20(asset()).balanceOf(address(this));
  }

  function getRadiantRewardNativeTokenAddresses()
    external
    view
    returns (address[6] memory)
  {
    return radiantRewardNativeTokenAddresses;
  }

  function _zapIn(uint256 amount) internal override returns (uint256) {
    uint256 currentAllowance = WETH.allowance(address(this), address(lockZap));
    if (currentAllowance > 0) {
      SafeERC20.safeApprove(WETH, address(lockZap), 0);
    }
    SafeERC20.safeApprove(WETH, address(lockZap), amount);
    uint256 shares = lockZap.zap(false, amount, 0, 3);
    return shares;
  }

  function redeem() public override {
    // TODO(david): should only redeem _shares amount of dLP
    uint256 radiantDlpShares = MULTIFEE_DISTRIBUTION
      .withdrawExpiredLocksForWithOptions(address(this), 1, true);
    require(radiantDlpShares != 0, "dLP lock has not expired yet");
    super.redeem(radiantDlpShares, msg.sender, msg.sender);
    claim();
  }

  function claim() public override {
    IFeeDistribution.RewardData[]
      memory claimableRewards = getClaimableRewards();
    if (claimableRewards.length != 0) {
      MULTIFEE_DISTRIBUTION.getAllRewards();
      super.claimRewardsFromVaultToPortfolioVault(claimableRewards);
    }
  }

  function getClaimableRewards()
    public
    view
    override
    returns (IFeeDistribution.RewardData[] memory rewards)
  {
    // pro rata: portfolio's share / total shares in this vault
    uint256 portfolioSharesInThisVault = balanceOf(msg.sender);
    uint256 totalVaultShares = totalSupply();
    // slither-disable-next-line incorrect-equality
    if (portfolioSharesInThisVault == 0 || totalVaultShares == 0) {
      return new IFeeDistribution.RewardData[](0);
    }
    IFeeDistribution.RewardData[]
      memory radiantRewardData = MULTIFEE_DISTRIBUTION.claimableRewards(
        address(this)
      );
    return
      _calculateClaimableRewards(
        radiantRewardData,
        portfolioSharesInThisVault,
        totalVaultShares
      );
  }

  function _calculateClaimableRewards(
    IFeeDistribution.RewardData[] memory radiantRewardData,
    uint256 portfolioSharesInThisVault,
    uint256 totalVaultShares
  ) internal pure returns (IFeeDistribution.RewardData[] memory rewards) {
    for (uint256 i = 0; i < radiantRewardData.length; i++) {
      // slither-disable-next-line incorrect-equality
      if (radiantRewardData[i].amount == 0) {
        continue;
      }
      radiantRewardData[i].amount = Math.mulDiv(
        radiantRewardData[i].amount,
        portfolioSharesInThisVault,
        totalVaultShares
      );
    }
    return radiantRewardData;
  }
}

