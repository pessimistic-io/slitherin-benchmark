// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import { IStaker, IRewardDistributor_v2, IFeeClaimer } from "./interfaces.sol";
import { IRewardsCalculator } from "./RewardsCalculator.sol";

contract SpaFeeClaimer is Initializable, OwnableUpgradeable, UUPSUpgradeable, IFeeClaimer {
  uint256 private constant FEE_DIVISOR = 1e4;
  IERC20 public constant REWARD_TOKEN = IERC20(0x5575552988A3A80504bBaeB1311674fCFd40aD4B);
  address public constant STAKER = 0x46ac70bf830896EEB2a2e4CBe29cD05628824928;
  IRewardDistributor_v2 public constant UNDERLYING_FARM =
    IRewardDistributor_v2(0xC9869e40e36A18546Df54A941B28aF21674aE512);

  uint32 public fee; // fee in bp
  address public feeCollector;
  address public rewardsDistro;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();
    fee = 2000;
  }

  function harvest() external {
    if (msg.sender != rewardsDistro) revert UNAUTHORIZED();

    (uint256 totalRewardsEarnedByStaker, uint256 lastRewardCollectionTime, uint256 rewardsTill) = UNDERLYING_FARM
      .computeRewards(STAKER);

    if (lastRewardCollectionTime < rewardsTill && isNotZero(totalRewardsEarnedByStaker)) {
      uint256 yield = IStaker(STAKER).claimFees(address(UNDERLYING_FARM), address(REWARD_TOKEN), address(this));

      unchecked {
        uint256 protocolFee = (yield * fee) / FEE_DIVISOR;
        REWARD_TOKEN.transfer(feeCollector, protocolFee);

        uint256 pendingRewardsLessFee = yield - protocolFee;
        REWARD_TOKEN.transfer(rewardsDistro, pendingRewardsLessFee);
        emit RewardsClaimed(pendingRewardsLessFee, protocolFee);
      }
    }
  }

  /** VIEWS */
  function pendingRewards() external view returns (uint256 pendingRewardsLessFee, uint256 protocolFee) {
    (uint256 totalRewardsEarnedByStaker, , ) = UNDERLYING_FARM.computeRewards(STAKER);

    unchecked {
      protocolFee = (totalRewardsEarnedByStaker * fee) / FEE_DIVISOR;
      pendingRewardsLessFee = totalRewardsEarnedByStaker - protocolFee;
    }
  }

  /** CHECKS */
  function isNotZero(uint256 _num) private pure returns (bool result) {
    assembly {
      result := gt(_num, 0)
    }
  }

  function isZero(uint256 _num) private pure returns (bool result) {
    assembly {
      result := iszero(_num)
    }
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  /**
    Owner can retrieve stuck funds
   */
  function retrieve(IERC20 token) external onlyOwner {
    if (isNotZero(address(this).balance)) {
      payable(owner()).transfer(address(this).balance);
    }

    token.transfer(owner(), token.balanceOf(address(this)));
  }

  function setFee(uint32 _fee) external onlyOwner {
    if (_fee > FEE_DIVISOR) {
      revert INVALID_FEE();
    }

    emit FeeChanged(_fee, fee);
    fee = _fee;
  }

  function setFeeCollector(address _newFeeCollector) external onlyOwner {
    emit FeeCollectorChanged(_newFeeCollector, feeCollector);
    feeCollector = _newFeeCollector;
  }

  function setRewardsDistro(address _newRewardsDistro) external onlyOwner {
    emit RewardsDistroChanged(_newRewardsDistro, rewardsDistro);
    rewardsDistro = _newRewardsDistro;
  }

  event FeeCollectorChanged(address indexed _new, address _old);
  event RewardsDistroChanged(address indexed _new, address _old);
  event FeeChanged(uint256 indexed _new, uint256 _old);
  event RewardsClaimed(uint256 _rewardsClaimedLessFee, uint256 _protocolFee);

  error INVALID_FEE();
  error UNAUTHORIZED();
}

