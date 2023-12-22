// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./ERC4626.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./IERC20Metadata.sol";
import "./AbstractVault.sol";
import "./IEqbZap.sol";
import "./IBaseRewardPool.sol";
import "./IEqbMinterSidechain.sol";
import "./IPendleBoosterSidechain.sol";
import "./IXEqbToken.sol";
import "./IPendleRouter.sol";
import "./IPendleBooster.sol";

abstract contract BaseEquilibriaVault is AbstractVault {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  IEqbZap public immutable eqbZap;
  IPendleBooster public immutable pendleBooster;
  uint256 public pid;
  address public eqbMinterAddr;
  address public pendleBoosterAddr;
  address public constant PENDLE_TOKEN_ADDR =
    0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8;
  address public constant EQB_TOKEN_ADDR =
    0xBfbCFe8873fE28Dfa25f1099282b088D52bbAD9C;
  address public constant XEQB_TOKEN_ADDR =
    0x96C4A48Abdf781e9c931cfA92EC0167Ba219ad8E;
  bool private _initialized = false;

  constructor(
    IERC20Metadata asset_,
    string memory name_,
    string memory symbol_
  ) ERC4626(asset_) ERC20(name_, symbol_) {
    eqbZap = IEqbZap(0xc7517f481Cc0a645e63f870830A4B2e580421e32);
    pendleBooster = IPendleBooster(0x4D32C8Ff2fACC771eC7Efc70d6A8468bC30C26bF);
  }

  modifier onlyOnce() {
    require(!_initialized, "Already initialized");
    _;
    _initialized = true;
  }

  function _initializePid(uint256 pid_) internal onlyOnce onlyOwner {
    pid = pid_;
  }

  function updateEqbMinterAddr(address eqbMinterAddr_) public onlyOwner {
    require(eqbMinterAddr_ != address(0), "Address cannot be zero");
    eqbMinterAddr = eqbMinterAddr_;
  }

  function updatePendleBoosterAddr(
    address pendleBoosterAddr_
  ) public onlyOwner {
    require(pendleBoosterAddr_ != address(0), "Address cannot be zero");
    pendleBoosterAddr = pendleBoosterAddr_;
  }

  function totalLockedAssets() public pure override returns (uint256) {
    return 0;
  }

  function totalStakedButWithoutLockedAssets()
    public
    view
    override
    returns (uint256)
  {
    // slither-disable-next-line unused-return
    (, , address rewardPool, ) = pendleBooster.poolInfo(pid);
    return IERC20(rewardPool).balanceOf(address(this));
  }

  // function getEqbReward() public view returns (uint256) {

  //   uint256 sum = EqbMinter.getFactor/EqbMinter.DENOMINATOR * PENDLE;
  //   uint256 EQB = Sum * PendleBooster.farmEqbShare/PendleBooster.DENOMINATOR;
  //   uint256 xEQB = Sum - EQB;
  // }

  function _zapIn(
    IERC20 zapInToken,
    uint256 amount,
    uint256 minLpOut,
    IPendleRouter.ApproxParams calldata guessPtReceivedFromSy,
    IPendleRouter.TokenInput calldata input
  ) internal override returns (uint256) {
    uint256 originalShares = totalStakedButWithoutLockedAssets();
    uint256 currentAllowance = zapInToken.allowance(
      address(this),
      address(eqbZap)
    );
    if (currentAllowance > 0) {
      SafeERC20.safeApprove(zapInToken, address(eqbZap), 0);
    }
    SafeERC20.safeApprove(zapInToken, address(eqbZap), amount);
    // Error: VM Exception while processing transaction: reverted with an unrecognized custom error (return data: 0xfa711db2)
    // It means the swap would exceed the max slippage
    eqbZap.zapIn(pid, minLpOut, guessPtReceivedFromSy, input, true);
    return totalStakedButWithoutLockedAssets().sub(originalShares);
  }

  function redeem(uint256 shares) public override {
    // slither-disable-next-line unused-return
    (, , address rewardPool, ) = pendleBooster.poolInfo(pid);
    uint256 currentAllowance = IBaseRewardPool(rewardPool)
      .stakingToken()
      .allowance(address(this), address(eqbZap));
    if (currentAllowance > 0) {
      SafeERC20.safeApprove(
        IBaseRewardPool(rewardPool).stakingToken(),
        address(eqbZap),
        0
      );
    }
    SafeERC20.safeApprove(
      IBaseRewardPool(rewardPool).stakingToken(),
      address(eqbZap),
      shares
    );
    eqbZap.withdraw(pid, shares);
    claim();
    super.redeem(shares, msg.sender, msg.sender);
  }

  function claim() public override {
    IFeeDistribution.RewardData[]
      memory claimableRewards = getClaimableRewards();
    if (claimableRewards.length != 0) {
      uint256[] memory pids = new uint256[](1);
      pids[0] = pid;
      eqbZap.claimRewards(pids);
      super.claimRewardsFromVaultToPortfolioVault(claimableRewards);
    }
  }

  function getClaimableRewards()
    public
    view
    override
    returns (IFeeDistribution.RewardData[] memory rewards)
  {
    // pro rata: user's share divided by total shares, is the ratio of the reward
    uint256 portfolioSharesInThisVault = balanceOf(msg.sender);
    uint256 totalVaultShares = totalSupply();
    // slither-disable-next-line incorrect-equality
    if (portfolioSharesInThisVault == 0 || totalVaultShares == 0) {
      return new IFeeDistribution.RewardData[](0);
    }
    // slither-disable-next-line unused-return
    (, , address rewardPool, ) = pendleBooster.poolInfo(pid);
    address[] memory rewardTokens = IBaseRewardPool(rewardPool)
      .getRewardTokens();
    // leave 2 spaces for EQB and xEQB
    rewards = new IFeeDistribution.RewardData[](rewardTokens.length + 1);
    uint256 pendleAmount = 0;
    for (uint256 i = 0; i < rewardTokens.length; i++) {
      // slither-disable-next-line calls-loop
      rewards[i] = IFeeDistribution.RewardData({
        token: rewardTokens[i],
        amount: Math.mulDiv(
          IBaseRewardPool(rewardPool).earned(address(this), rewardTokens[i]),
          portfolioSharesInThisVault,
          totalVaultShares
        )
      });
      if (rewardTokens[i] == PENDLE_TOKEN_ADDR) {
        pendleAmount = rewards[i].amount;
      }
    }
    uint256 eqbAmount = _getEqbClaimableRewards(pendleAmount);
    rewards[rewardTokens.length] = IFeeDistribution.RewardData({
      token: EQB_TOKEN_ADDR,
      amount: eqbAmount
    });
    return rewards;
  }

  function redeemXEQB(uint256 amount, uint256 duration) external onlyOwner {
    IXEqbToken(XEQB_TOKEN_ADDR).redeem(amount, duration);
  }

  function finalizeRedeem(uint256 redeemIndex) external onlyOwner {
    IXEqbToken(XEQB_TOKEN_ADDR).finalizeRedeem(redeemIndex);
    SafeERC20.safeTransfer(
      IERC20(EQB_TOKEN_ADDR),
      msg.sender,
      IERC20(EQB_TOKEN_ADDR).balanceOf(address(this))
    );
  }

  function _getEqbClaimableRewards(
    uint256 pendleAmount
  ) internal view returns (uint256) {
    uint256 sumOfEqbAndXeqb = Math.mulDiv(
      pendleAmount,
      IEqbMinterSidechain(eqbMinterAddr).getFactor(),
      IEqbMinterSidechain(eqbMinterAddr).DENOMINATOR()
    );
    uint256 eqbAmount = Math.mulDiv(
      sumOfEqbAndXeqb,
      IPendleBoosterSidechain(pendleBoosterAddr).farmEqbShare(),
      IPendleBoosterSidechain(pendleBoosterAddr).DENOMINATOR()
    );
    // formula: xeqbAmount = sumOfEqbAndXeqb - eqbAmount
    return eqbAmount;
  }
}

