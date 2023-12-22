// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IStaker.sol";
import "./IMillinerV2.sol";

interface IJonesStaker {
  function harvest() external;

  function pendingRewardsLessFee() external view returns (uint256);

  function jonesPerSecondLessFee() external view returns (uint256);
}

contract JonesStaker is IStaker, IJonesStaker, Ownable {
  uint256 public constant POOL_ID = 1;
  uint256 private constant FEE_DIVISOR = 1e4;

  // WETH-JONES SLP: 0xe8EE01aE5959D3231506FcDeF2d5F3E85987a39c
  IERC20 public immutable stakingToken;

  // JONES: 0x10393c20975cF177a3513071bC110f7962CD67da
  IERC20 public immutable rewardToken;

  // MillinerV2: 0xb94d1959084081c5a11C460012Ab522F5a0FD756
  IMillinerV2 public immutable underlyingFarm;

  address public operator;
  address public feeCollector;
  address public rewardsDistro;

  uint128 public fee; // fee in bp
  uint128 public totalHarvested;

  constructor(
    address _feeCollector,
    address _stakingToken,
    address _rewardToken,
    address _underlyingFarm
  ) {
    feeCollector = _feeCollector;

    stakingToken = IERC20(_stakingToken);
    rewardToken = IERC20(_rewardToken);
    underlyingFarm = IMillinerV2(_underlyingFarm);
    fee = 1000; // 10%

    stakingToken.approve(address(underlyingFarm), type(uint256).max);
  }

  function stake(uint256 _amount) external {
    if (msg.sender != operator) {
      revert UNAUTHORIZED();
    }

    underlyingFarm.deposit(POOL_ID, _amount);
    emit Staked(_amount);
  }

  function withdraw(uint256 _amount, address _to) external {
    if (msg.sender != operator) {
      revert UNAUTHORIZED();
    }

    underlyingFarm.withdraw(POOL_ID, _amount);
    stakingToken.transfer(_to, _amount);
    emit Withdrew(_to, _amount);
  }

  function harvest() external {
    if (msg.sender != rewardsDistro) revert UNAUTHORIZED();
    _harvest();
  }

  /** VIEWS */
  function pendingRewardsLessFee() external view returns (uint256) {
    unchecked {
      return (underlyingFarm.pendingJones(POOL_ID, msg.sender) * (FEE_DIVISOR - fee)) / FEE_DIVISOR;
    }
  }

  function jonesPerSecondLessFee() external view returns (uint256) {
    unchecked {
      return (underlyingFarm.jonesPerSecond() * (FEE_DIVISOR - fee)) / FEE_DIVISOR;
    }
  }

  /** PRIVATE FUNCTIONS */
  function _harvest() private {
    underlyingFarm.harvest(POOL_ID);

    uint256 rewardAmt = rewardToken.balanceOf(address(this));
    uint256 rewardAmtLessFee;

    if (isNotZero(rewardAmt)) {
      unchecked {
        uint256 feePayable = (rewardAmt * fee) / FEE_DIVISOR;

        rewardAmtLessFee = rewardAmt - feePayable;
        totalHarvested += uint128(rewardAmtLessFee);

        if (isNotZero(feePayable)) {
          rewardToken.transfer(feeCollector, feePayable);
        }

        rewardToken.transfer(address(rewardsDistro), rewardAmtLessFee);
        emit Harvested(address(rewardToken), rewardAmtLessFee);
      }
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

  /**
    Retrieve stuck funds or new reward tokens
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
    uint256 balance = underlyingFarm.deposited(POOL_ID, address(this));
    address owner = owner();

    underlyingFarm.withdraw(POOL_ID, balance);
    stakingToken.transfer(owner, balance);
    emit ExitedStaking(owner, balance);

    _harvest();
  }

  function setFee(uint128 _fee) external onlyOwner {
    if (_fee > FEE_DIVISOR) {
      revert INVALID_FEE();
    }

    emit FeeChanged(_fee, fee);
    fee = _fee;
  }

  function ownerHarvest() external onlyOwner {
    _harvest();
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
    emit RewardsDistroChanged(_newRewardsDistro, rewardsDistro);
    rewardsDistro = _newRewardsDistro;
  }

  event Staked(uint256 _amt);
  event Withdrew(address indexed _to, uint256 _amt);
  event OperatorChanged(address indexed _new, address _old);
  event FeeCollectorChanged(address indexed _new, address _old);
  event RewardsDistroChanged(address indexed _new, address _old);
  event FeeChanged(uint256 indexed _new, uint256 _old);
  event ExitedStaking(address indexed _to, uint256 _amt);
  event Harvested(address indexed _token, uint256 _amt);

  error UNAUTHORIZED();
  error INVALID_FEE();
}

