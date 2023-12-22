//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./Math.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./BaseUpgradeableStrategy.sol";
import "./ICamelotRouter.sol";
import "./ICamelotPair.sol";
import "./INFTPool.sol";
import "./INitroPool.sol";
import "./IVault.sol";
import "./IPotPool.sol";
import "./IUniversalLiquidator.sol";

contract CamelotNitroIFarmStrategy is BaseUpgradeableStrategy {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant camelotRouter = address(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
  address public constant xGrail = address(0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b);
  address public constant iFarm = address(0x9dCA587dc65AC0a043828B0acd946d71eb8D46c1);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _POS_ID_SLOT = 0x025da88341279feed86c02593d3d75bb35ff95cb72e32ffd093929b008413de5;
  bytes32 internal constant _NFT_POOL_SLOT = 0x828d9a241b00468f203e6001f37c2f3f9b054802b5bfa652f8dee2a0f2d586d9;
  bytes32 internal constant _NITRO_POOL_SLOT = 0x1ee567d62ee6cf3d5c44deeb8b6f34774a4a2d99f55ae3d5f1ca16bee430b005;
  bytes32 internal constant _XGRAIL_VAULT_SLOT = 0xd445aff5601e22e4f2e49f44eb54e33aa29670745d5241914b5369f65f9d43d0;
  bytes32 internal constant _POTPOOL_SLOT = 0x7f4b50847e7d7a4da6a6ea36bfb188c77e9f093697337eb9a876744f926dd014;

  // this would be reset on each upgrade
  address[] public rewardTokens;

  constructor() public BaseUpgradeableStrategy() {
    assert(_POS_ID_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.posId")) - 1));
    assert(_NFT_POOL_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.nftPool")) - 1));
    assert(_NITRO_POOL_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.nitroPool")) - 1));
    assert(_XGRAIL_VAULT_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.xGrailVault")) - 1));
    assert(_POTPOOL_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.potPool")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _grail,
    address _nftPool,
    address _nitroPool,
    address _xGrailVault,
    address _potPool
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _nitroPool,
      _grail,
      harvestMSIG
    );

    address _lpt;
    (_lpt,,,,,,,) = INFTPool(_nftPool).getPoolInfo();
    require(_lpt == underlying(), "NFTPool Info does not match underlying");
    address checkNftPool = INitroPool(_nitroPool).nftPool();
    require(checkNftPool == _nftPool, "NitroPool does not match NFTPool");
    _setNFTPool(_nftPool);
    _setNitroPool(_nitroPool);
    setAddress(_XGRAIL_VAULT_SLOT, _xGrailVault);
    setAddress(_POTPOOL_SLOT, _potPool);
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function rewardPoolBalance() internal view returns (uint256 bal) {
    (bal,,,,) = INitroPool(nitroPool()).userInfo(address(this));
  }

  function exitRewardPool() internal {
    uint256 stakedBalance = rewardPoolBalance();
    if (stakedBalance != 0) {
      uint256 _posId = posId();
      INitroPool(nitroPool()).withdraw(_posId);
      INFTPool(nftPool()).withdrawFromPosition(_posId, stakedBalance);
    }
  }

  function partialWithdrawalRewardPool(uint256 amount) internal {
      uint256 _posId = posId();
      address _nitroPool = nitroPool();
      address _nftPool = nftPool();
      INitroPool(_nitroPool).withdraw(_posId);
      INFTPool(_nftPool).withdrawFromPosition(_posId, amount);
      INFTPool(_nftPool).safeTransferFrom(address(this), _nitroPool, _posId);
  }

  function emergencyExitRewardPool() internal {
    uint256 stakedBalance = rewardPoolBalance();
    if (stakedBalance != 0) {
      uint256 _posId = posId();
      INitroPool(nitroPool()).emergencyWithdraw(_posId);
      INFTPool(nftPool()).emergencyWithdraw(_posId);
    }
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying());
  }

  function enterRewardPool() internal {
    address _underlying = underlying();
    address _nftPool = nftPool();
    address _nitroPool = nitroPool();
    uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));
    IERC20(_underlying).safeApprove(_nftPool, 0);
    IERC20(_underlying).safeApprove(_nftPool, entireBalance);
    uint256 _posId = posId();
    if (_posId > 0) {  //We already have a position. Withdraw from staking, add to position, stake again.
      INitroPool(_nitroPool).withdraw(_posId);
      INFTPool(_nftPool).addToPosition(_posId, entireBalance);
      INFTPool(_nftPool).safeTransferFrom(address(this), _nitroPool, _posId);
    } else {                        //We do not yet have a position. Create a position and store the position ID. Then stake.
      INFTPool(_nftPool).createPosition(entireBalance, 0);
      uint256 newPosId = INFTPool(_nftPool).tokenOfOwnerByIndex(address(this), 0);
      _setPosId(newPosId);
      INFTPool(_nftPool).safeTransferFrom(address(this), _nitroPool, posId());
    }
  }

  function updateNitroPool(address newNitroPool) external onlyGovernance {
    address _nitroPool = nitroPool();
    uint256 _posId = posId();
    if (_posId > 0) {
      INitroPool(_nitroPool).harvest();
      INitroPool(_nitroPool).withdraw(_posId);
    }
    _setNitroPool(newNitroPool);
    INFTPool(nftPool()).safeTransferFrom(address(this), nitroPool(), _posId);
  }

  /*
  *   In case there are some issues discovered about the pool or underlying asset
  *   Governance can exit the pool properly
  *   The function is only used for emergency to exit the pool
  */
  function emergencyExit() public onlyGovernance {
    emergencyExitRewardPool();
    _setPausedInvesting(true);
  }

  /*
  *   Resumes the ability to invest into the underlying reward pools
  */

  function continueInvesting() public onlyGovernance {
    _setPausedInvesting(false);
  }

  function addRewardToken(address _token) public onlyGovernance {
    rewardTokens.push(_token);
  }

  function _claimRewards() internal {
    uint256 _posId = posId();
    if (_posId > 0){
      address _nitroPool = nitroPool();
      address _nftPool = nftPool();
      INitroPool(_nitroPool).harvest();
      INitroPool(_nitroPool).withdraw(_posId);
      INFTPool(_nftPool).harvestPosition(_posId);
      INFTPool(_nftPool).safeTransferFrom(address(this), _nitroPool, _posId);
    }
  }

  function _liquidateRewards(uint256 _xGrailAmount) internal {
    address _rewardToken = rewardToken();
    address _universalLiquidator = universalLiquidator();
    for (uint256 i; i < rewardTokens.length; i++) {
      address token = rewardTokens[i];
      uint256 balance = IERC20(token).balanceOf(address(this));
      if (balance == 0) {
          continue;
      }
      if (token != _rewardToken){
          IERC20(token).safeApprove(_universalLiquidator, 0);
          IERC20(token).safeApprove(_universalLiquidator, balance);
          IUniversalLiquidator(_universalLiquidator).swap(token, _rewardToken, balance, 1, address(this));
      }
    }

    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_rewardToken, rewardBalance.add(_xGrailAmount));
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
    IERC20(_rewardToken).safeApprove(_universalLiquidator, remainingRewardBalance);

    address _underlying = underlying();

    address token0 = ICamelotPair(_underlying).token0();
    address token1 = ICamelotPair(_underlying).token1();

    uint256 toToken0 = remainingRewardBalance.div(2);
    uint256 toToken1 = remainingRewardBalance.sub(toToken0);

    uint256 token0Amount;
    if (_rewardToken != token0) {
      IUniversalLiquidator(_universalLiquidator).swap(_rewardToken, token0, toToken0, 1, address(this));
      token0Amount = IERC20(token0).balanceOf(address(this));
    } else {
      token0Amount = toToken0;
    }

    uint256 token1Amount;
    if (_rewardToken != token1) {
      IUniversalLiquidator(_universalLiquidator).swap(_rewardToken, token1, toToken1, 1, address(this));
      token1Amount = IERC20(token1).balanceOf(address(this));
    } else {
      token1Amount = toToken1;
    }

    IERC20(token0).safeApprove(camelotRouter, 0);
    IERC20(token0).safeApprove(camelotRouter, token0Amount);

    IERC20(token1).safeApprove(camelotRouter, 0);
    IERC20(token1).safeApprove(camelotRouter, token1Amount);

    ICamelotRouter(camelotRouter).addLiquidity(
      token0,
      token1,
      token0Amount,
      token1Amount,
      1,
      1,
      address(this),
      block.timestamp
    );

    _handleXGrail();
  }

  function _handleXGrail() internal {
    uint256 balance = IERC20(xGrail).balanceOf(address(this));
    if (balance == 0) { return; }
    address _xGrailVault = xGrailVault();
    address _potPool = potPool();

    IERC20(xGrail).safeApprove(_xGrailVault, 0);
    IERC20(xGrail).safeApprove(_xGrailVault, balance);
    IVault(_xGrailVault).deposit(balance);

    uint256 vaultBalance = IERC20(_xGrailVault).balanceOf(address(this));
    IERC20(_xGrailVault).safeTransfer(_potPool, vaultBalance);
    IPotPool(_potPool).notifyTargetRewardAmount(_xGrailVault, vaultBalance);

    uint256 iFarmBalance = IERC20(iFarm).balanceOf(address(this));
    IERC20(iFarm).safeTransfer(_potPool, iFarmBalance);
    IPotPool(_potPool).notifyTargetRewardAmount(iFarm, iFarmBalance);
  }

  /*
  *   Stakes everything the strategy holds into the reward pool
  */
  function investAllUnderlying() internal onlyNotPausedInvesting {
    // this check is needed, because most of the SNX reward pools will revert if
    // you try to stake(0).
    if(IERC20(underlying()).balanceOf(address(this)) > 0) {
      enterRewardPool();
    }
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawAllToVault() public restricted {
    address _underlying = underlying();
    if (address(rewardPool()) != address(0)) {
      exitRewardPool();
    }
    uint256 xGrailReward = IERC20(xGrail).balanceOf(address(this));
    _liquidateRewards(xGrailReward);
    IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawToVault(uint256 amount) public restricted {
    address _underlying = underlying();
    // Typically there wouldn't be any amount here
    // however, it is possible because of the emergencyExit
    uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));

    if(amount > entireBalance){
      // While we have the check above, we still using SafeMath below
      // for the peace of mind (in case something gets changed in between)
      uint256 needToWithdraw = amount.sub(entireBalance);
      uint256 toWithdraw = Math.min(rewardPoolBalance(), needToWithdraw);
      partialWithdrawalRewardPool(toWithdraw);
    }
    IERC20(_underlying).safeTransfer(vault(), amount);
  }

  /*
  *   Note that we currently do not have a mechanism here to include the
  *   amount of reward that is accrued.
  */
  function investedUnderlyingBalance() external view returns (uint256) {
    return rewardPoolBalance()
      .add(IERC20(underlying()).balanceOf(address(this)));
  }

  /*
  *   Governance or Controller can claim coins that are somehow transferred into the contract
  *   Note that they cannot come in take away coins that are used and defined in the strategy itself
  */
  function salvage(address recipient, address token, uint256 amount) external onlyControllerOrGovernance {
     // To make sure that governance cannot come in and take away the coins
    require(!unsalvagableTokens(token), "token is defined as not salvagable");
    IERC20(token).safeTransfer(recipient, amount);
  }

  /*
  *   Get the reward, sell it in exchange for underlying, invest what you got.
  *   It's not much, but it's honest work.
  *
  *   Note that although `onlyNotPausedInvesting` is not added here,
  *   calling `investAllUnderlying()` affectively blocks the usage of `doHardWork`
  *   when the investing is being paused by governance.
  */
  function doHardWork() external onlyNotPausedInvesting restricted {
    _claimRewards();
    uint256 xGrailReward = IERC20(xGrail).balanceOf(address(this));
    _liquidateRewards(xGrailReward);
    investAllUnderlying();
  }

  function _setPosId(uint256 _value) internal {
    setUint256(_POS_ID_SLOT, _value);
  }

  function posId() public view returns (uint256) {
    return getUint256(_POS_ID_SLOT);
  }

  function _setNFTPool(address _address) internal {
    setAddress(_NFT_POOL_SLOT, _address);
  }

  function nftPool() public view returns (address) {
    return getAddress(_NFT_POOL_SLOT);
  }

  function _setNitroPool(address _address) internal {
    setAddress(_NITRO_POOL_SLOT, _address);
  }

  function nitroPool() public view returns (address) {
    return getAddress(_NITRO_POOL_SLOT);
  }

  function setXGrailVault(address _value) public onlyGovernance {
    require(xGrailVault() == address(0), "Hodl vault already set");
    setAddress(_XGRAIL_VAULT_SLOT, _value);
  }

  function xGrailVault() public view returns (address) {
    return getAddress(_XGRAIL_VAULT_SLOT);
  }

  function setPotPool(address _value) public onlyGovernance {
    require(potPool() == address(0), "PotPool already set");
    setAddress(_POTPOOL_SLOT, _value);
  }

  function potPool() public view returns (address) {
    return getAddress(_POTPOOL_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  receive() external payable {} // this is needed for the WETH unwrapping

  bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;
  function onERC721Received(address /*operator*/, address /*from*/, uint256 /*tokenId*/, bytes calldata /*data*/) external pure returns (bytes4) {
    return _ERC721_RECEIVED;
  }

  function onNFTHarvest(address /*operator*/, address /*to*/, uint256 /*tokenId*/, uint256 /*grailAmount*/, uint256 /*xGrailAmount*/) external pure returns (bool) {return true;}
  function onNFTAddToPosition(address /*operator*/, uint256 /*tokenId*/, uint256 /*lpAmount*/) external pure returns (bool) {return true;}
  function onNFTWithdraw(address /*operator*/, uint256 /*tokenId*/, uint256 /*lpAmount*/) external pure returns (bool) {return true;}
}
