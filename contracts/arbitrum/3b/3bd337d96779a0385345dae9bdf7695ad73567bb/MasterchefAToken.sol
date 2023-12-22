// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IERC20} from "./IERC20.sol";
import {AToken} from "./AToken.sol";
import {IMiniChefV2} from "./IMiniChefV2.sol";
import {FeeBase} from "./FeeBase.sol";
import {IPool} from "./IPool.sol";
import {IAaveIncentivesController} from "./IAaveIncentivesController.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {GPv2SafeERC20} from "./GPv2SafeERC20.sol";

/**
 * @title MasterChef ERC20 AToken
 * @author MahaDAO
 * @notice Implementation of the interest bearing token that stakes a LP token into a MasterChef contract
 */
contract MasterchefAToken is AToken, FeeBase {
  using WadRayMath for uint256;
  using GPv2SafeERC20 for IERC20;

  uint256 public pid;
  IMiniChefV2 public chef; // Sushiswap masterChef
  IERC20 public rewardToken; // sushi

  uint256 private constant _NOT_ENTERED = 1;
  uint256 private constant _ENTERED = 2;
  uint256 private _status;

  constructor(IPool pool) AToken(pool) {
    // Intentionally left blank
  }

    function getRevision() internal pure virtual override returns (uint256) {
    return 2;
  }

  function initialize(
    IPool initializingPool,
    address treasury,
    address underlyingAsset,
    IAaveIncentivesController incentivesController,
    uint8 aTokenDecimals,
    string calldata aTokenName,
    string calldata aTokenSymbol,
    bytes calldata params
  ) public virtual override initializer {
    super.initialize(
      initializingPool,
      treasury,
      underlyingAsset,
      incentivesController,
      aTokenDecimals,
      aTokenName,
      aTokenSymbol,
      params
    );

    (
      uint256 _rewardFeeRate,
      uint256 _pid,
      address _rewardFeeDestination,
      address _chef,
      address _rewardToken
    ) = abi.decode(params, (uint256, uint256, address, address, address));

    initializeFeeBase(_rewardFeeRate, _rewardFeeDestination);

    chef = IMiniChefV2(_chef);
    rewardToken = IERC20(_rewardToken);
    pid = _pid;

    _status = _NOT_ENTERED;

    // give max approval to sushi contract
    IERC20(underlyingAsset).approve(_chef, type(uint256).max);
  }

  /**
   * @dev Prevents a contract from calling itself, directly or indirectly.
   * Calling a `nonReentrant` function from another `nonReentrant`
   * function is not supported. It is possible to prevent this from happening
   * by making the `nonReentrant` function external, and making it call a
   * `private` function that does the actual work.
   */
  modifier nonReentrant() {
    _nonReentrantBefore();
    _;
    _nonReentrantAfter();
  }

  function _nonReentrantBefore() private {
    // On the first call to nonReentrant, _status will be _NOT_ENTERED
    require(_status != _ENTERED, 'ReentrancyGuard: reentrant call');

    // Any calls to nonReentrant after this point will fail
    _status = _ENTERED;
  }

  function _nonReentrantAfter() private {
    // By storing the original value once again, a refund is triggered (see
    // https://eips.ethereum.org/EIPS/eip-2200)
    _status = _NOT_ENTERED;
  }

  /**
   * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
   * `nonReentrant` function in the call stack.
   */
  function _reentrancyGuardEntered() internal view returns (bool) {
    return _status == _ENTERED;
  }

  function mint(
    address caller,
    address onBehalfOf,
    uint256 amount,
    uint256 index
  ) external virtual override nonReentrant onlyPool returns (bool) {
    uint256 amountScaled = amount.rayDiv(index);

    // stake into the masterchef contract
    chef.deposit(pid, amountScaled, address(this));

    // inherit mint code from aToken
    return _mintScaled(caller, onBehalfOf, amount, index);
  }

  function burn(
    address from,
    address receiverOfUnderlying,
    uint256 amount,
    uint256 index
  ) external virtual override nonReentrant onlyPool {
    // withdraw lp from masterchef
    chef.withdraw(pid, amount, address(this));

    // harvest rewards
    harvest();

    // calculate accumulated rewards and send the rewards
    uint256 earnings = _accumulatedRewardsForAmount(amount);
    rewardToken.transfer(receiverOfUnderlying, earnings);

    // inherit burn code from aToken
    _burnScaled(from, receiverOfUnderlying, amount, index);
    if (receiverOfUnderlying != address(this)) {
      IERC20(_underlyingAsset).safeTransfer(receiverOfUnderlying, amount);
    }
  }

  function rewardTokenBalance() public view returns (uint256) {
    return rewardToken.balanceOf(address(this));
  }

  // capture rewards and send the fees to the governance contract
  function harvest() public {
    uint256 balBefore = rewardTokenBalance();
    chef.harvest(pid, address(this));
    uint256 earnings = rewardTokenBalance() - (balBefore);
    _chargeFee(rewardToken, earnings);
  }

  function _accumulatedRewards() internal view virtual returns (uint256) {
    return chef.pendingSushi(pid, address(this)) + rewardTokenBalance();
  }

  function accumulatedRewards() external view returns (uint256) {
    return _accumulatedRewards();
  }

  function accumulatedRewardsFor(address _user) external view returns (uint256) {
    return _accumulatedRewardsFor(_user);
  }

  function _accumulatedRewardsFor(address _user) internal view returns (uint256) {
    uint256 bal = balanceOf(_user);
    return _accumulatedRewardsForAmount(bal);
  }

  function _accumulatedRewardsForAmount(uint256 bal) internal view returns (uint256) {
    uint256 accRewards = _accumulatedRewards();
    uint256 total = totalSupply();
    uint256 perc = (bal * 1e18) / (total);
    return (accRewards * perc) / (1e18);
  }

  function setRewardFeeRate(uint256 _new) external onlyPoolAdmin {
    _setRewardFeeRate(_new);
  }

  function setRewardFeeAddress(address _new) external onlyPoolAdmin {
    _setRewardFeeAddress(_new);
  }
}

