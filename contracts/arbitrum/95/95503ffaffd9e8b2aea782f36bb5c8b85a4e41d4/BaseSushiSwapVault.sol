// SPDX-License-Identifier: MIT
// This is a Smart Contract written in Solidity. It represents a vault that allows users to deposit WETH and receive DPXV in return. The contract uses the functionalities of other smart contracts such as oneInch aggregator, SushiSwap, and MiniChefV2 to perform swaps and farming of SUSHI and DPX tokens. The contract has several functions including deposit(), redeem(), claim(), totalAssets(), totalLockedAssets(), totalStakedButWithoutLockedAssets(), and getClaimableRewards().

pragma solidity 0.8.18;

import "./ERC4626.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./IERC20Metadata.sol";

import "./IMiniChefV2.sol";
import "./ICloneRewarderTime.sol";
import "./SafeMath.sol";
import "./Math.sol";
import "./IUniswapV2Router01.sol";
import "./IWETH.sol";
import "./AbstractVault.sol";
import "./IFeeDistribution.sol";

contract BaseSushiSwapVault is AbstractVault {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);

  /**
   * @dev Attempted to deposit more assets than the max amount for `receiver`.
   */
  error ERC4626ExceededMaxDeposit(
    address receiver,
    uint256 assets,
    uint256 max
  );

  IERC20 public token_consists_of_lp;
  IERC20 public constant SUSHI_TOKEN =
    IERC20(0xd4d42F0b6DEF4CE0383636770eF773390d85c61A);
  address public constant SUSHISWAP_ROUTER_ADDRESS =
    0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

  ICloneRewarderTime public rewarder;
  IMiniChefV2 public constant sushiSwapMiniChef =
    IMiniChefV2(0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3);

  uint256 public pid; // sushiSwap pid
  mapping(string => bool) private _initialized;

  modifier onlyOnce(string memory key) {
    require(!_initialized[key], "Already initialized");
    _;
    _initialized[key] = true;
  }

  constructor(
    IERC20Metadata asset_,
    string memory name_,
    string memory symbol_
  ) ERC4626(asset_) ERC20(name_, symbol_) {}

  function _initializePid(uint256 pid_) internal onlyOnce("pid") onlyOwner {
    pid = pid_;
  }

  function _initializeLpTokenAndRewarder(
    address token_consists_of_lp_,
    address rewarder_
  ) internal onlyOnce("rewarder") onlyOwner {
    token_consists_of_lp = IERC20(token_consists_of_lp_);
    rewarder = ICloneRewarderTime(rewarder_);
  }

  function _zapIn(
    uint256 amount,
    bytes calldata oneInchData
  ) internal override returns (uint256) {
    uint256 wethAllowance = WETH.allowance(
      address(this),
      oneInchAggregatorAddress
    );
    if (wethAllowance > 0) {
      SafeERC20.safeApprove(WETH, oneInchAggregatorAddress, 0);
    }
    SafeERC20.safeApprove(
      WETH,
      oneInchAggregatorAddress,
      Math.mulDiv(amount, 1, 2)
    );
    // slither-disable-next-line low-level-calls
    (bool succ, bytes memory data) = address(oneInchAggregatorAddress).call(
      oneInchData
    );
    require(
      succ,
      "1inch failed to swap, please update your block_number when running hardhat test"
    );
    uint256 tokenReturnedAmount = abi.decode(data, (uint256));
    uint256 tokenAllowance = token_consists_of_lp.allowance(
      address(this),
      SUSHISWAP_ROUTER_ADDRESS
    );
    if (tokenAllowance > 0) {
      SafeERC20.safeApprove(token_consists_of_lp, SUSHISWAP_ROUTER_ADDRESS, 0);
    }
    SafeERC20.safeApprove(
      token_consists_of_lp,
      SUSHISWAP_ROUTER_ADDRESS,
      tokenReturnedAmount
    );
    WETH.withdraw(Math.mulDiv(amount, 1, 2));

    // deadline means current time + 5 minutes;
    // solhint-disable-next-line not-rely-on-time
    uint256 deadline = block.timestamp + 300;

    // slither-disable-next-line unused-return
    (, , uint liquidity) = IUniswapV2Router01(SUSHISWAP_ROUTER_ADDRESS)
      .addLiquidityETH{value: address(this).balance}(
      address(token_consists_of_lp),
      tokenReturnedAmount,
      Math.mulDiv(tokenReturnedAmount, 95, 100),
      Math.mulDiv(address(this).balance, 95, 100),
      address(this),
      deadline
    );
    uint256 slpAllowance = IERC20(asset()).allowance(
      address(this),
      address(sushiSwapMiniChef)
    );
    if (slpAllowance > 0) {
      SafeERC20.safeApprove(IERC20(asset()), address(sushiSwapMiniChef), 0);
    }
    SafeERC20.safeApprove(
      IERC20(asset()),
      address(sushiSwapMiniChef),
      liquidity
    );
    sushiSwapMiniChef.deposit(pid, liquidity, address(this));
    return liquidity;
  }

  function redeem(uint256 shares) public override {
    sushiSwapMiniChef.withdrawAndHarvest(pid, shares, address(this));
    super.redeem(shares, msg.sender, msg.sender);
  }

  function claim() public override {
    // TODO(david): current implementation doesn't support multiple portfolio vaults
    // since harvet() would harvest all of the rewards, which is owned by multiple portfolio vaults
    // claimRewardsFromVaultToPortfolioVault need to also transfer the reward balance, residing in this contract. Not just those claimableRewards.
    IFeeDistribution.RewardData[]
      memory claimableRewards = getClaimableRewards();
    if (claimableRewards.length != 0) {
      sushiSwapMiniChef.harvest(pid, address(this));
      super.claimRewardsFromVaultToPortfolioVault(claimableRewards);
    }
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
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of SUSHI entitled to the user.
    // slither-disable-next-line unused-return
    (uint256 amount, ) = sushiSwapMiniChef.userInfo(pid, address(this));
    return amount;
  }

  function totalUnstakedAssets() public view override returns (uint256) {
    return IERC20(asset()).balanceOf(address(this));
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
    rewards = new IFeeDistribution.RewardData[](2);
    rewards[0] = IFeeDistribution.RewardData({
      token: address(SUSHI_TOKEN),
      amount: Math.mulDiv(
        sushiSwapMiniChef.pendingSushi(pid, address(this)),
        portfolioSharesInThisVault,
        totalVaultShares
      )
    });
    rewards[1] = IFeeDistribution.RewardData({
      token: address(token_consists_of_lp),
      amount: Math.mulDiv(
        rewarder.pendingToken(pid, address(this)),
        portfolioSharesInThisVault,
        totalVaultShares
      )
    });
    return rewards;
  }

  // To receive ETH from the WETH's withdraw function (it won't work without it)
  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}
}

