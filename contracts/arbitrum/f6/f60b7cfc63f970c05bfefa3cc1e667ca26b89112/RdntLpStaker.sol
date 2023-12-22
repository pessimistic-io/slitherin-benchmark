// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./IERC20.sol";
import { IMultiFeeDistribution, IChefIncentivesController, ILendingPool } from "./Radiant.sol";
import { IDelegation, IRdntLpStaker, IPlsRdntUtils, IAToken } from "./Interfaces.sol";

contract RdntLpStaker is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IRdntLpStaker {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

  IERC20 public constant DLP = IERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);
  uint public constant MAX_LOCK_TYPEINDEX = 3;
  IMultiFeeDistribution public constant UNDERLYING_FARM =
    IMultiFeeDistribution(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE); // protocol fees
  IChefIncentivesController public constant UNDERLYING_FARM_2 =
    IChefIncentivesController(0xebC85d44cefb1293707b11f707bd3CEc34B4D5fA); // rdnt emissions
  ILendingPool public constant LENDING_POOL = ILendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);
  IPlsRdntUtils public constant UTILS = IPlsRdntUtils(0x1f3Fa65C5A9cf4f295fc34329aeA552a528d7ac3);

  address public depositor;
  address public operator;
  uint32 public fee; // UNUSED
  EnumerableSetUpgradeable.AddressSet private rewardTokens;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable2Step_init();
    __UUPSUpgradeable_init();

    DLP.approve(address(UNDERLYING_FARM), type(uint).max);
    UNDERLYING_FARM.setDefaultRelockTypeIndex(MAX_LOCK_TYPEINDEX);
    UNDERLYING_FARM.setRelock(true);
    fee = 1200;

    rewardTokens.add(0x3082CC23568eA640225c2467653dB90e9250AaA0);
    rewardTokens.add(0x727354712BDFcd8596a3852Fd2065b3C34F4F770);
    rewardTokens.add(0xd69D402D1bDB9A2b8c3d88D98b9CEaf9e4Cd72d9);
    rewardTokens.add(0x48a29E756CC1C097388f3B2f3b570ED270423b3d);
    rewardTokens.add(0x0D914606f3424804FA1BbBE56CCC3416733acEC6);
    rewardTokens.add(0x0dF5dfd95966753f01cb80E76dc20EA958238C46);
  }

  function stake(uint _amount) external {
    if (msg.sender != depositor) revert UNAUTHORIZED();
    UNDERLYING_FARM.stake(_amount, address(this), MAX_LOCK_TYPEINDEX);
  }

  /**
   * @notice Claim radiant protocol fees
   * @param _to address that unwrapped rewards go to
   * @return _rewardsData RewardData{address token, uint amount}[] with a length equal to RewardTokenCount(). tokens are underlying asset, amount may be 0.
   */
  function claimRadiantProtocolFees(
    address _to
  ) external returns (IMultiFeeDistribution.RewardData[] memory _rewardsData) {
    if (msg.sender != operator) revert UNAUTHORIZED();

    _rewardsData = UTILS.mfdClaimableRewards(address(this), getRewardTokens());
    UNDERLYING_FARM.getReward(getRewardTokens());

    for (uint i; i < _rewardsData.length; i = _unsafeInc(i)) {
      uint _amount = _rewardsData[i].amount;

      if (_amount > 0) {
        // unwrap - Assets are 1:1. Update return array to reflect underlying asset address
        _rewardsData[i].token = IAToken(_rewardsData[i].token).UNDERLYING_ASSET_ADDRESS();
        LENDING_POOL.withdraw(_rewardsData[i].token, _amount, _to);
      }
    }
  }

  function getRewardTokens() public view returns (address[] memory rewardTokenArr) {
    uint len = rewardTokens.length();
    rewardTokenArr = new address[](len);

    for (uint i; i < len; i = _unsafeInc(i)) {
      rewardTokenArr[i] = rewardTokens.at(i);
    }
  }

  function getRewardTokenCount() external view returns (uint) {
    return rewardTokens.length();
  }

  function _unsafeInc(uint x) private pure returns (uint) {
    unchecked {
      return x + 1;
    }
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }

  function approveATokens() external onlyOwner {
    address[] memory _rewardTokens = getRewardTokens();
    for (uint i; i < _rewardTokens.length; i = _unsafeInc(i)) {
      IERC20(_rewardTokens[i]).approve(address(LENDING_POOL), type(uint256).max);
    }
  }

  function addReward(address _rewardToken) external onlyOwner {
    if (rewardTokens.contains(_rewardToken)) revert FAILED('RdntLpStaker: Reward Token exists');

    rewardTokens.add(_rewardToken);
    IERC20(_rewardToken).approve(address(LENDING_POOL), type(uint256).max);
  }

  function removeReward(address _rewardToken) external onlyOwner {
    rewardTokens.remove(_rewardToken);
    IERC20(_rewardToken).approve(address(LENDING_POOL), 0);
  }

  function setDelegate(address _delegate) external onlyOwner {
    IDelegation(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446).setDelegate('radiantcapital.eth', _delegate);
  }

  function setOperator(address _newOperator) external onlyOwner {
    emit OperatorChanged(_newOperator, operator);
    operator = _newOperator;
  }

  function setDepositor(address _newDepositor) external onlyOwner {
    emit DepositorChanged(_newDepositor, depositor);
    depositor = _newDepositor;
  }

  event OperatorChanged(address indexed _new, address _old);
  event DepositorChanged(address indexed _new, address _old);

  error UNAUTHORIZED();

  error FAILED(string reason);
}

