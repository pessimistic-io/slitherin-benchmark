// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Math.sol";
import "./IWrappedGLP.sol";
import "./IGlpRewardTracker.sol";

contract CarbonWrappedGLP is ERC20, ReentrancyGuard, Ownable, Pausable, IWrappedGLP {
  using SafeERC20 for IERC20;
  using Math for uint256;

  address GLP_MANAGER_ADDRESS = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;

  IGlpRewardTracker public constant glpRewardTracker = IGlpRewardTracker(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
  IGlpRewardTracker public constant glpStakeRouter = IGlpRewardTracker(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
  IERC20 public constant wETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  IERC20 public constant fsGLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903); // GLP balance
  IERC20 public constant sGLP = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);  // GLP token

  constructor()
  ERC20("Carbon Wrapped GLP", "cGLP")
  {
    sGLP.approve(address(this), type(uint256).max);
    wETH.approve(address(GLP_MANAGER_ADDRESS), type(uint256).max);
  }

  /** @dev Convenience method to deposit all available assets. */
  function depositAll() external {
    deposit(fsGLP.balanceOf(msg.sender), msg.sender);
  }

  /** @dev Convenience method to redeem all available shares. */
  function redeemAll() external {
    redeem(balanceOf(msg.sender), msg.sender, msg.sender);
  }

  /** @dev See {IERC4626-deposit}. */
  function deposit(uint256 assets, address receiver) public whenNotPaused nonReentrant returns (uint256) {
    require(assets >= 1 ether, "CarbonWrappedGLP: minimum deposit required");

    _compound();

    uint256 shares = previewDeposit(assets);
    sGLP.safeTransferFrom(msg.sender, address(this), assets);
    _mint(receiver, shares);

    emit Deposit(msg.sender, receiver, assets, shares);

    return shares;
  }

  /** @dev See {IERC4626-redeem}. */
  function redeem(uint256 shares, address receiver, address owner) public whenNotPaused nonReentrant returns (uint256) {
    if (msg.sender != owner) {
      _spendAllowance(owner, msg.sender, shares);
    }

    _compound();

    uint256 assets = previewRedeem(shares);
    _burn(owner, shares);
    sGLP.safeTransferFrom(address(this), receiver, assets);

    emit Withdraw(msg.sender, receiver, owner, assets, shares);

    return assets;
  }

  /** @dev Redeem function to allow withdrawal of assets
   *  without compounding rewards.
   */
  function redeemWithoutCompound(uint256 shares) public nonReentrant returns (uint256) {
    uint256 assets = previewRedeem(shares);
    _burn(msg.sender, shares);
    sGLP.safeTransferFrom(address(this), msg.sender, assets);

    emit Withdraw(msg.sender, msg.sender, msg.sender, assets, shares);

    return assets;
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

  /** @dev Compound rewards into GLP */
  function compound() external whenNotPaused nonReentrant returns (uint256) {
   return _compound();
  }

  function _compound() internal returns (uint256) {
    // compound rewards
    glpRewardTracker.compound();
    glpRewardTracker.claimFees();

    uint256 wethAmount = wETH.balanceOf(address(this));

    if (wethAmount == 0) return 0;

    uint256 newGlp = glpStakeRouter.mintAndStakeGlp(address(wETH), wethAmount, 0, 0);

    emit Compound(
      msg.sender,

      // total wETH compounded
      wethAmount,

      // total new GLP added to vault
      newGlp
    );

    return newGlp;
  }

  function setPaused(bool pause) external onlyOwner {
    if (pause) {
      _pause();
    } else {
      _unpause();
    }
  }

  function emergencyRetrieve(address tokenAddress, address payable recipient, uint256 amount) external onlyOwner {
    // disable vault asset withdraw
    require(tokenAddress != address(sGLP), "CarbonWrappedGLP: cannot emergency retrieve asset");
    
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

