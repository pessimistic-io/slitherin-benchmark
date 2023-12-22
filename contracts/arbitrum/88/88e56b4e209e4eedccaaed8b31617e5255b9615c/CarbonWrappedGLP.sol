// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ISwapRouter.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Math.sol";
import "./CarbonWrappedERC20.sol";
import "./IWrappedGLP.sol";
import "./IGlpRewardTracker.sol";

interface IWETH is IERC20 {
  function withdrawTo(address account, uint256 amount) external;
}

contract CarbonWrappedGLP is CarbonWrappedERC20, IWrappedGLP, Pausable {
  using SafeERC20 for IERC20;
  using Math for uint256;

  address GLP_MANAGER_ADDRESS = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;

  IGlpRewardTracker private constant glpRewardTracker = IGlpRewardTracker(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
  IGlpRewardTracker private constant glpStakeRouter = IGlpRewardTracker(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
  ISwapRouter private constant uniswapRouter = ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
  IWETH private constant wETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  IERC20 private constant GMX = IERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);  // GMX token
  IERC20 public constant fsGLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903); // GLP balance
  IERC20 public constant sGLP = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);  // GLP token

  bool public autoCompoundMode = true;

  constructor(address lockProxyAddress)
  CarbonWrappedERC20(lockProxyAddress, "zABC Token", "zABC")
  {
    sGLP.approve(address(this), type(uint256).max);
    wETH.approve(address(uniswapRouter), type(uint256).max);
    wETH.approve(address(GLP_MANAGER_ADDRESS), type(uint256).max);
  }

  /** @dev See {IERC4626-deposit}. */
  function deposit(uint256 assets, address receiver) public whenNotPaused returns (uint256) {
    require(assets >= 1 ether, "Minimum deposit");

    // this.handleRewards();

    uint256 shares = previewDeposit(assets);
    sGLP.safeTransferFrom(msg.sender, address(this), assets);
    _mint(receiver, shares);

    emit Deposit(msg.sender, receiver, assets, shares);

    return shares;
  }

  /** @dev See {IERC4626-redeem}. */
  function redeem(uint256 shares, address receiver, address owner) public whenNotPaused returns (uint256) {
    if (msg.sender != owner) {
      _spendAllowance(owner, msg.sender, shares);
    }

    // this.handleRewards();

    uint256 assets = previewRedeem(shares);
    _burn(owner, shares);
    sGLP.safeTransferFrom(address(this), receiver, assets);

    emit Withdraw(msg.sender, receiver, owner, assets, shares);

    return shares;
  }

  /** @dev See {IERC4626-previewDeposit}. */
  function previewDeposit(uint256 assets) public view virtual returns (uint256) {
      return _convertToShares(assets, Math.Rounding.Down);
  }
  
  /** @dev See {IERC4626-previewRedeem}. */
  function previewRedeem(uint256 assets) public view virtual returns (uint256) {
      return _convertToAssets(assets, Math.Rounding.Down);
  }

  /**
   * @dev Ref {IERC4626-_convertToAssets}.
   * @dev Internal conversion function (from shares to assets) with support for rounding direction.
   */
  function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256 assets) {
    uint256 supply = totalSupply();
    return (supply == 0) ? shares : shares.mulDiv(totalAssets(), supply, rounding);
  }

  /**
   * @dev Ref {IERC4626-_convertToShares}.
   * @dev Internal conversion function (from assets to shares) with support for rounding direction.
   *
   * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
   * would represent an infinite amount of shares.
   */
  function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256 shares) {
    uint256 supply = totalSupply();
    return (assets == 0 || supply == 0) ? assets : assets.mulDiv(supply, totalAssets(), rounding);
  }

  /** @dev See {IERC4626-totalAssets}. */
  function totalAssets() public view virtual returns (uint256) {
      return fsGLP.balanceOf(address(this));
  }

  function compoundRewards() external returns (uint256) {
    glpRewardTracker.handleRewards(true, false, true, true, false, true, false);

    uint256 gmxRewards = GMX.balanceOf(address(this));
    uint256 wethFromGmx = 0;
    if (gmxRewards > 0) {
      ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
        tokenIn: address(GMX),
        tokenOut: address(wETH),
        fee: 3000,
        recipient: address(this),
        deadline: block.timestamp,
        amountIn: gmxRewards,
        amountOutMinimum: 0, // TODO update min out
        sqrtPriceLimitX96: 0
      });
      wethFromGmx = uniswapRouter.exactInputSingle(params);
    }

    uint256 wethRewards = wETH.balanceOf(address(this));
    uint256 totalWeth = wethFromGmx + wethRewards;
    if (totalWeth == 0) return 0;

    uint256 newGlp = glpStakeRouter.mintAndStakeGlp(address(wETH), totalWeth, 0, 0); // TODO update min glp

    emit Harvested(msg.sender, gmxRewards, wethRewards, wethFromGmx, newGlp);

    return newGlp;
  }

  function depositAll() external {
    deposit(fsGLP.balanceOf(msg.sender), msg.sender);
  }

  function redeemAll() external {
    redeem(balanceOf(msg.sender), msg.sender, msg.sender);
  }

  function setPaused(bool pause) external onlyOwner {
    if (pause) {
      _pause();
    } else {
      _unpause();
    }
  }

  function retrieve(address tokenAddress, address payable recipient, uint256 amount) external onlyOwner {
    if (tokenAddress == address(0)) {
      recipient.transfer(address(this).balance);
    } else {
      IERC20 token = IERC20(tokenAddress);

      if (amount == 0) {
        amount = token.balanceOf(address(this));
      }

      token.transfer(owner(), amount);
    }
  } 
}

