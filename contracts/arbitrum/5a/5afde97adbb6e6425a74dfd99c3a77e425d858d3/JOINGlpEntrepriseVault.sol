// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./AccessControl.sol";
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

interface ICompounding {
  function compound(uint256 glpPerEtherPrice) external; // 18 decimal places
}

contract JOINGlpEntrepriseVault is ERC4626, AccessControl, Ownable {

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  bytes32 public constant COMPOUND_ROLE = keccak256("COMPOUND_ROLE");

  ERC20 public constant WETH = ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  ERC20 public constant GLP = ERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903); // Fee + Staked GLP (fsGLP)
  ERC20 public constant SGLP = ERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);

  IRewardRouterV2 public glpRewardRouterV2 = IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
  IRewardTracker public rewardTracker = IRewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);

  ICompounding public compoundingContract;
  uint256 public totalHarvested;
  uint256 public accumulatedVaultFee;
  uint256 fee; // in bips
  address private feeWallet;
  address public wrapper;

  event GlpRewardRouterUpdated(address updater, address newRewardRouter);
  event Harvest(uint256 amount);
  event Fee(uint256 amount);
  event RewardTrackerUpdated(address updater, address newRewardTracker);
  event CompoundingContractUpdated(address updater, address newYieldStrategy);
  event WrapperContractUpdated(address updater, address newWrapperContract);

  constructor() ERC20("TJGLP", "tjGLP") ERC4626(GLP) Ownable() {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }


  function _deposit(
    address caller,
    address receiver,
    uint256 assets,
    uint256 shares
  ) internal virtual override {
    require(msg.sender == wrapper, "Not Authorized");

    SafeERC20.safeTransferFrom(SGLP, caller, address(this), assets);
    _mint(receiver, shares);

    emit Deposit(caller, receiver, assets, shares);
  }

  function _withdraw(
      address caller,
      address receiver,
      address owner,
      uint256 assets,
      uint256 shares
  ) internal virtual override {
    require(msg.sender == wrapper, "Not Authorized");
    if (caller != owner) {
      _spendAllowance(owner, caller, shares);
    }
    _burn(owner, shares);
    SafeERC20.safeTransfer(SGLP, receiver, assets);

    emit Withdraw(caller, receiver, owner, assets, shares);
  }

  // INTERNAL FUNCTIONS // ---------------------------------------------------------- //

  // Harvest the yeild earned on GLP deposits. Yield is paid in WETH.
  function harvest() internal {
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
    uint256 harvestReceived = balanceAfter-balanceBefore;
    if(harvestReceived == 0) {
      return; // nothing to do
    }
    uint256 harvestFee = harvestReceived*fee/10000;
    uint256 harvestedEthAmount = harvestReceived-harvestFee;
    totalHarvested += harvestedEthAmount; //totalHarvested just stores the lifetime harvest value, variable has no other use.
    accumulatedVaultFee += harvestFee;
    emit Harvest(harvestedEthAmount);
    emit Fee(harvestFee);
    WETH.transfer(address(compoundingContract), harvestedEthAmount);
  }

  // SCHEDULED FUNCTIONS // ---------------------------------------------------------- //

  function sheduledHarvestAndCompound(uint256 _glpPerEtherPrice) external onlyRole(COMPOUND_ROLE) {
    harvest();
    compoundingContract.compound(_glpPerEtherPrice);
  }

  // ADMIN FUNCTIONS // ---------------------------------------------------------- //

  function withdrawFee() external onlyOwner {
    if(accumulatedVaultFee > 0) {
      WETH.transfer(feeWallet, accumulatedVaultFee);
      accumulatedVaultFee = 0;
    }   
  }

  function setCompoundingContract(address _newAddress) public onlyRole(ADMIN_ROLE) {
    compoundingContract = ICompounding(_newAddress);
    emit CompoundingContractUpdated(msg.sender, address(compoundingContract));
  }

  function setGlpRewardRouter(address _newAddress) public onlyRole(ADMIN_ROLE) {
    glpRewardRouterV2 = IRewardRouterV2(_newAddress);
    emit GlpRewardRouterUpdated(msg.sender, address(glpRewardRouterV2));
  }

  function setGlpRewardTracker(address _newAddress) public onlyRole(ADMIN_ROLE) {
    rewardTracker = IRewardTracker(_newAddress);
    emit RewardTrackerUpdated(msg.sender, address(rewardTracker));
  }

  function setFee(uint256 _fee) public onlyRole(ADMIN_ROLE) {
    fee = _fee;
  }

  function setFeeWallet(address _feeWallet) public onlyRole(ADMIN_ROLE) {
    feeWallet = _feeWallet;
  }

  // recover cannot acces GLP/sGLP so admin can't rug depositors
  function recover(address _tokenAddress) public onlyRole(ADMIN_ROLE) {
    require(_tokenAddress != address(GLP) && _tokenAddress != address(SGLP), "admin cannot move GLP");
    IERC20(_tokenAddress).transfer(msg.sender, IERC20(_tokenAddress).balanceOf(address(this)));
  }

  function recoverETH(address payable _to) public onlyRole(ADMIN_ROLE) payable {
    (bool sent,) = _to.call{ value: address(this).balance }("");
    require(sent, "failed to send ETH");
  }

  function setWrapper(address _wrapper) public onlyRole(ADMIN_ROLE) {
    wrapper = _wrapper;
    emit WrapperContractUpdated(msg.sender, _wrapper);
  }
}

