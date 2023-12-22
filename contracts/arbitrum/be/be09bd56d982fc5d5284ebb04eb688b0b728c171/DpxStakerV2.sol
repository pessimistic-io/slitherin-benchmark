// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Ownable.sol";
import { IStaker, IDPXVotingEscrow, IVoting, IFeeDistro } from "./interfaces.sol";

contract DpxStakerV2 is Ownable, IStaker {
  uint256 private constant MAXTIME = 4 * 365 * 86400;
  uint256 private constant WEEK = 7 * 86400;

  IERC20 public immutable dpx;
  address public immutable escrow;
  address public depositor;
  address public operator;
  address public gaugeController;
  address public voter;

  uint208 public unlockTime;
  uint32 public newMaxTime;
  bool public maxTimeChanged;

  constructor(address _dpx, address _escrow) {
    dpx = IERC20(_dpx);
    escrow = _escrow;
    dpx.approve(escrow, type(uint256).max);
  }

  function stake(uint256 _amount) external {
    if (msg.sender != depositor) revert UNAUTHORIZED();

    IERC20(dpx).balanceOf(address(this));

    // increase amount
    IDPXVotingEscrow(escrow).increase_amount(_amount);

    uint256 unlockAt = block.timestamp + MAXTIME;

    // accomodate future change in max locking time
    if (maxTimeChanged) {
      unlockAt = block.timestamp + uint256(newMaxTime);
    }

    uint256 unlockInWeeks = (unlockAt / WEEK) * WEEK;

    // increase time too if over 1 week buffer
    if (unlockInWeeks - unlockTime >= 1) {
      IDPXVotingEscrow(escrow).increase_unlock_time(unlockAt);
      unlockTime = uint208(unlockInWeeks);
    }
  }

  function voteGaugeWeight(address _gauge, uint256 _weight) external returns (bool) {
    if (msg.sender != voter) revert UNAUTHORIZED();
    IVoting(gaugeController).vote_for_gauge_weights(_gauge, _weight);
    return true;
  }

  function claimFees(
    address _distroContract,
    address _token,
    address _claimTo
  ) external returns (uint256) {
    if (msg.sender != operator) revert UNAUTHORIZED();
    IFeeDistro(_distroContract).getYield();
    uint256 _balance = IERC20(_token).balanceOf(address(this));
    IERC20(_token).transfer(_claimTo, _balance);
    return _balance;
  }

  function execute(
    address _to,
    uint256 _value,
    bytes calldata _data
  ) external returns (bool, bytes memory) {
    if (msg.sender != voter && msg.sender != operator) revert UNAUTHORIZED();
    (bool success, bytes memory result) = _to.call{ value: _value }(_data);
    return (success, result);
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
    Owner can retrieve stuck funds
   */
  function retrieve(IERC20 token) external onlyOwner {
    if (isNotZero(address(this).balance)) {
      payable(owner()).transfer(address(this).balance);
    }

    token.transfer(owner(), token.balanceOf(address(this)));
  }

  function initialLock(address _feeDistro) external onlyOwner {
    uint256 unlockAt = block.timestamp + MAXTIME;
    unlockTime = uint208((unlockAt / WEEK) * WEEK);
    IDPXVotingEscrow(escrow).create_lock(dpx.balanceOf(address(this)), unlockAt);
    IFeeDistro(_feeDistro).checkpoint();
  }

  function release() external onlyOwner {
    emit Release();
    IDPXVotingEscrow(escrow).withdraw();
  }

  function setOperator(address _newOperator) external onlyOwner {
    emit OperatorChanged(_newOperator, operator);
    operator = _newOperator;
  }

  function setDepositor(address _newDepositor) external onlyOwner {
    emit DepositorChanged(_newDepositor, depositor);
    depositor = _newDepositor;
  }

  function setVoter(address _newVoter) external onlyOwner {
    emit VoterChanged(_newVoter, voter);
    voter = _newVoter;
  }

  function setGaugeController(address _newGauge) external onlyOwner {
    emit GaugeChanged(_newGauge, gaugeController);
    gaugeController = _newGauge;
  }

  function setNewMaxTime(bool _changed, uint32 _newMaxTime) external onlyOwner {
    emit MaxTimeUpdated(_newMaxTime);
    maxTimeChanged = _changed;
    newMaxTime = _newMaxTime;
  }

  event MaxTimeUpdated(uint32 _newMaxTime);
  event Release();
  event GaugeChanged(address indexed _new, address _old);
  event VoterChanged(address indexed _new, address _old);
  event OperatorChanged(address indexed _new, address _old);
  event DepositorChanged(address indexed _new, address _old);

  error UNAUTHORIZED();
  error INVALID_FEE();
}

