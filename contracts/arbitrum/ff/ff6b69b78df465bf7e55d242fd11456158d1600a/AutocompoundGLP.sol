// SPDX-License-Identifier: AGPL-3.0-or-later
// unstoppablefinance.org
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./ERC4626.sol";

// GLP RewardRouterV2 minimal interface
interface IRewardRouterV2 {
  function handleRewards(
    bool _shouldClaimGmx,
    bool _shouldStakeGmx,
    bool _shouldClaimEsGmx,
    bool _shouldStakeEsGmx,
    bool _shouldStakeMultiplierPoints,
    bool _shouldClaimWeth,
    bool _shouldConvertWethToEth
  ) external;
}

interface IRewardTracker {
  function claimable(address _account) external view returns (uint256);
}

interface IStrategy {
  function compound() external;
}

/*******************************************************************************************
 * 
 * @title Unstoppable GLP Autocompounder
 * 
 * @author unstoppablefinance.org
 * 
 * @notice ERC4626 based vault that accepts gmx.io GLP token as base asset / principal.
 *         The ETH yield is harvested and sent to the strategy contract which compounds
 *         it for more GLP and sends it back to this vault.
 * 
 *******************************************************************************************/
contract GlpVault is ERC4626, Ownable { 

  ERC20 public constant WETH = ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  ERC20 public constant GLP = ERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903); // Fee + Staked GLP (fsGLP)
  ERC20 public constant SGLP = ERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);

  IRewardRouterV2 public glpRewardRouterV2 = IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
  IRewardTracker public rewardTracker = IRewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);

  IStrategy public yieldStrategy;

  uint256 public sensibleMinimumWethToHarvest = 1_000_000_000_000_000; // 0.001 WETH 

  uint256 public totalHarvested;
  uint256 public lastHarvestTimestamp;

  event GlpRewardRouterUpdated(address updater, address newRewardRouter);
  event Harvest(uint256 amount);
  event RewardTrackerUpdated(address updater, address newRewardTracker);
  event SensibleMinimumWethToHarvest(address updater, uint256 newMinimum);
  event YieldStrategyUpdated(address updater, address newYieldStrategy);

  constructor(string memory _name, string memory _symbol, address _yieldStrategy) 
    ERC20(_name, _symbol) 
    ERC4626(GLP) 
    Ownable() {
    yieldStrategy = IStrategy(_yieldStrategy);
  }

  /**********************************************************************************
   *
   * @dev we need to override ERC4626 methods _deposit and _withdraw to use 
   * SGLP.transferFrom instead of GLP.transferFrom since GLP token is staked 
   * by default to receive fees and not directlty transferrable while staked.
   * 
   * See https://gmxio.gitbook.io/gmx/contracts#transferring-staked-glp for details.
   * 
   * We also call harvestTransferAndCompound() on every deposit.
   * 
  ***********************************************************************************/
  function _deposit(
    address caller,
    address receiver,
    uint256 assets,
    uint256 shares
  ) internal virtual override {
    harvestTransferAndCompound();

    SafeERC20.safeTransferFrom(SGLP, caller, address(this), assets);
    _mint(receiver, shares);

    emit Deposit(caller, receiver, assets, shares);
  }

  // @dev we don't call harvestTransferAndCompound() on withdraw so users funds are not locked
  // in case it reverts somewhere downstream
  function _withdraw(
      address caller,
      address receiver,
      address owner,
      uint256 assets,
      uint256 shares
  ) internal virtual override {
    if (caller != owner) {
      _spendAllowance(owner, caller, shares);
    }
    _burn(owner, shares);
    SafeERC20.safeTransfer(SGLP, receiver, assets);

    emit Withdraw(caller, receiver, owner, assets, shares);
  }

  /********************************************************
   * 
   * @dev First we harvest WETH from GMX (if any is available)
   * then we transfer the WETH to the strategy contract
   * and trigger the compounding in the strategy.
   * 
  *********************************************************/
  function harvestTransferAndCompound() public {
    harvest();
    transferHarvestedFundsToStrategy();
    yieldStrategy.compound();
  }

  // @dev compounds esGMX & multiplier points and sends weth to address(this)
  function harvest() public {
    uint256 harvestableAmount = rewardTracker.claimable(address(this));
    if(harvestableAmount == 0 || harvestableAmount < sensibleMinimumWethToHarvest) {
      return; // nothing to do
    }

    lastHarvestTimestamp = block.timestamp;
    uint256 balanceBefore = WETH.balanceOf(address(this));

    glpRewardRouterV2.handleRewards(
      false, // _shouldClaimGmx
      false, // _shoudlStakeGmx
      true, // _shouldClaimEsGmx
      true, // _shouldStakeEsGmx
      true, // _shouldStakeMultiplierPoints
      true, // _shouldClaimWeth
      false // _shouldConvertWethToEth
    );

    uint256 balanceAfter = WETH.balanceOf(address(this));
    uint256 harvestedEthAmount = balanceAfter-balanceBefore;
    totalHarvested += harvestedEthAmount;

    emit Harvest(harvestedEthAmount);
  }

  function transferHarvestedFundsToStrategy() public {
    uint256 wethBalance = WETH.balanceOf(address(this));
    if(wethBalance == 0) {
      return; // nothing to do
    }

    WETH.transfer(address(yieldStrategy), wethBalance);
  }

  /*****************************
   * 
   *      ADMIN functions
   * 
   *****************************/
  function setYieldStrategy(address _newStrategy) public onlyOwner {
    yieldStrategy = IStrategy(_newStrategy);
    emit YieldStrategyUpdated(msg.sender, address(yieldStrategy));
  }

  function setGlpRewardRouter(address _newAddress) public onlyOwner {
    glpRewardRouterV2 = IRewardRouterV2(_newAddress);
    emit GlpRewardRouterUpdated(msg.sender, address(glpRewardRouterV2));
  }

  function setGlpRewardTracker(address _newAddress) public onlyOwner {
    rewardTracker = IRewardTracker(_newAddress);
    emit RewardTrackerUpdated(msg.sender, address(rewardTracker));
  }

  function setSensibleMinimumWethToHarvest(uint _newValue) public onlyOwner {
    sensibleMinimumWethToHarvest = _newValue;
    emit SensibleMinimumWethToHarvest(msg.sender, sensibleMinimumWethToHarvest);
  }

  // recover cannot acces GLP/sGLP so admin can't rug depositors
  function recover(address _tokenAddress) public onlyOwner {
    require(_tokenAddress != address(GLP) && _tokenAddress != address(SGLP), "admin cannot move GLP");
    IERC20(_tokenAddress).transfer(msg.sender, IERC20(_tokenAddress).balanceOf(address(this)));
  }

  function recoverETH(address payable _to) public onlyOwner payable {
    (bool sent,) = _to.call{ value: address(this).balance }("");
    require(sent, "failed to send ETH");
  }
}
