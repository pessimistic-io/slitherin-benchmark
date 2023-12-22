// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import { IStaker, IDPXVotingEscrow, IFeeDistro } from "./interfaces.sol";

contract DpxStakerV2 is Initializable, OwnableUpgradeable, UUPSUpgradeable, IStaker {
  uint256 private constant WEEK = 7 * 86400;
  uint256 public constant MAXTIME = 4 * 365 * 86400;
  IERC20 public constant dpx = IERC20(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55);
  address public constant escrow = 0x80789D252A288E93b01D82373d767D71a75D9F16;

  address public depositor;
  address public operator;
  uint256 public unlockTime;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    dpx.approve(escrow, type(uint256).max);
    __Ownable_init();
    __UUPSUpgradeable_init();
  }

  function stake(uint256 _amount) external {
    if (msg.sender != depositor) revert UNAUTHORIZED();

    // increase amount
    IDPXVotingEscrow(escrow).increase_amount(_amount);

    unchecked {
      uint256 unlockAt = block.timestamp + MAXTIME;
      uint256 unlockInWeeks = (unlockAt / WEEK) * WEEK;

      // increase time too if over 1 week buffer
      if (unlockInWeeks - unlockTime >= 1) {
        IDPXVotingEscrow(escrow).increase_unlock_time(unlockAt);
        unlockTime = unlockInWeeks;
      }
    }
  }

  function maxLock() external returns (bool) {
    if (msg.sender != operator) revert UNAUTHORIZED();

    unchecked {
      uint256 unlockAt = block.timestamp + MAXTIME;
      uint256 unlockInWeeks = (unlockAt / WEEK) * WEEK;

      IDPXVotingEscrow(escrow).increase_unlock_time(unlockAt);
      unlockTime = unlockInWeeks;
    }

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

  function initialLock(address _feeDistro) external onlyOwner {
    uint256 unlockAt = block.timestamp + MAXTIME;
    unlockTime = (unlockAt / WEEK) * WEEK;
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

  event Release();
  event OperatorChanged(address indexed _new, address _old);
  event DepositorChanged(address indexed _new, address _old);

  error UNAUTHORIZED();
  error INVALID_FEE();
}

