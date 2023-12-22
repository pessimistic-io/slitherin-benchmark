// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./IStaker.sol";
import "./IDpxStakingRewards.sol";
import "./IPlsDpxRewardsDistro.sol";

contract DpxStaker is IStaker, Ownable, ReentrancyGuard {
  // DPX: 0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55
  IERC20 public immutable stakingToken;

  // DPX: 0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55
  IERC20 public immutable rewardToken;

  // rDPX: 0x32Eb7902D4134bf98A28b963D26de779AF92A212
  IERC20 public immutable rewardToken2;

  // StakingRewards: 0xc6D714170fE766691670f12c2b45C1f34405AAb6
  IDpxStakingRewards public immutable underlyingFarm;

  address public operator;
  address public feeCollector;
  IPlsDpxRewardsDistro public rewardsDistro;

  uint256 public fee; // fee in bp

  constructor(
    address _feeCollector,
    address _dpx,
    address _rdpx,
    address _underlyingFarm
  ) {
    feeCollector = _feeCollector;

    stakingToken = IERC20(_dpx);
    rewardToken = IERC20(_dpx);
    rewardToken2 = IERC20(_rdpx);
    underlyingFarm = IDpxStakingRewards(_underlyingFarm);
    fee = 1000; // 10%

    stakingToken.approve(address(underlyingFarm), type(uint256).max);
  }

  function stake(uint256 _amt) external {
    _checkOperator();

    underlyingFarm.stake(_amt);
    emit Staked(_amt);
  }

  function withdraw(uint256 _amount, address _to) external {
    _checkOperator();

    underlyingFarm.withdraw(_amount);
    stakingToken.transfer(_to, _amount);
  }

  function harvest() public nonReentrant {
    underlyingFarm.getReward(2);

    address _rewardsDistro = address(rewardsDistro);
    uint256 _fee = fee;

    uint256 r1Amt = rewardToken.balanceOf(address(this));
    uint256 r1AmtLessFee;

    if (isNotZero(r1Amt)) {
      unchecked {
        uint256 r1Fee = (r1Amt * _fee) / 1e4;

        if (isNotZero(r1Fee)) {
          rewardToken.transfer(feeCollector, r1Fee);
        }

        r1AmtLessFee = r1Amt - r1Fee;

        rewardToken.transfer(_rewardsDistro, r1AmtLessFee);
        emit Harvested(address(rewardToken), r1AmtLessFee);
      }
    }

    uint256 r2Amt = rewardToken2.balanceOf(address(this));
    uint256 r2AmtLessFee;

    if (isNotZero(r2Amt)) {
      unchecked {
        uint256 r2Fee = (r2Amt * _fee) / 1e4;

        if (isNotZero(r2Fee)) {
          rewardToken2.transfer(feeCollector, r2Fee);
        }

        r2AmtLessFee = r2Amt - r2Fee;

        rewardToken2.transfer(_rewardsDistro, r2AmtLessFee);
        emit Harvested(address(rewardToken), r2AmtLessFee);
      }
    }

    rewardsDistro.updateHarvestDetails(block.timestamp, r1AmtLessFee, r2AmtLessFee);
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

  function _checkOperator() private view {
    if (msg.sender != operator) {
      revert NOT_AUTHORIZED();
    }
  }

  /** OWNER FUNCTIONS */

  /**
    Owner can retrieve stuck funds
   */
  function retrieve(IERC20 token) external onlyOwner {
    if (isNotZero(address(this).balance)) {
      payable(owner()).transfer(address(this).balance);
    }

    token.transfer(owner(), token.balanceOf(address(this)));
  }

  /**
    Exit farm for veBoost migration
   */
  function exit() external onlyOwner {
    uint256 vaultBalance = underlyingFarm.balanceOf(address(this));
    address owner = owner();
    underlyingFarm.withdraw(vaultBalance);
    stakingToken.transfer(owner, vaultBalance);
    emit ExitedStaking(owner, vaultBalance);

    harvest();
  }

  function setFee(uint256 _fee) external onlyOwner {
    if (_fee > 1e4) {
      revert INVALID_FEE();
    }

    emit FeeChanged(_fee, fee);
    fee = _fee;
  }

  function setOperator(address _newOperator) external onlyOwner {
    emit OperatorChanged(_newOperator, operator);
    operator = _newOperator;
  }

  function setFeeCollector(address _newFeeCollector) external onlyOwner {
    emit FeeCollectorChanged(_newFeeCollector, feeCollector);
    feeCollector = _newFeeCollector;
  }

  function setRewardsDistro(address _newRewardsDistro) external onlyOwner {
    emit RewardsDistroChanged(_newRewardsDistro, address(rewardsDistro));
    rewardsDistro = IPlsDpxRewardsDistro(_newRewardsDistro);
  }

  event Staked(uint256 _amt);
  event OperatorChanged(address _new, address indexed _old);
  event FeeCollectorChanged(address _new, address indexed _old);
  event RewardsDistroChanged(address _new, address indexed _old);
  event FeeChanged(uint256 _new, uint256 _old);
  event ExitedStaking(address _to, uint256 _amt);
  event Harvested(address indexed _token, uint256 _amt);

  error NOT_AUTHORIZED();
  error INVALID_FEE();
}

