// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./AddressUpgradeable.sol";
import { IStaker, IveSPA, IRewardDistributor_v2 } from "./interfaces.sol";

contract SpaStaker is Initializable, OwnableUpgradeable, UUPSUpgradeable, IStaker {
  uint256 private constant WEEK = 7 * 86400;
  uint256 public constant MAXTIME = 4 * 365 * 86400;
  IERC20 public constant token = IERC20(0x5575552988A3A80504bBaeB1311674fCFd40aD4B);
  address public constant escrow = 0x2e2071180682Ce6C247B1eF93d382D509F5F6A17;

  address public depositor;
  address public operator;
  uint256 public unlockTime;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    token.approve(escrow, type(uint256).max);
    __Ownable_init();
    __UUPSUpgradeable_init();
  }

  function stake(uint256 _amount) external {
    if (msg.sender != depositor) revert UNAUTHORIZED();

    // increase amount
    IveSPA(escrow).increaseAmount(uint128(_amount));

    unchecked {
      uint256 unlockAt = block.timestamp + MAXTIME;
      uint256 unlockInWeeks = (unlockAt / WEEK) * WEEK;

      // increase time too if over 1 week buffer
      if (unlockInWeeks - unlockTime >= 1) {
        IveSPA(escrow).increaseUnlockTime(unlockAt);
        unlockTime = unlockInWeeks;
      }
    }
  }

  function maxLock() external returns (bool) {
    if (msg.sender != operator) revert UNAUTHORIZED();

    unchecked {
      uint256 unlockAt = block.timestamp + MAXTIME;
      uint256 unlockInWeeks = (unlockAt / WEEK) * WEEK;

      IveSPA(escrow).increaseUnlockTime(unlockAt);
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
    IRewardDistributor_v2(_distroContract).claim(false);
    uint256 _balance = IERC20(_token).balanceOf(address(this));

    if (isNotZero(_balance)) {
      IERC20(_token).transfer(_claimTo, _balance);
    }

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
  function retrieve(IERC20 _token) external onlyOwner {
    if (isNotZero(address(this).balance)) {
      AddressUpgradeable.sendValue(payable(owner()), address(this).balance);
    }

    token.transfer(owner(), _token.balanceOf(address(this)));
  }

  function initialLock() external onlyOwner {
    uint256 unlockAt = block.timestamp + MAXTIME;
    unlockTime = (unlockAt / WEEK) * WEEK;
    IveSPA(escrow).createLock(uint128(token.balanceOf(address(this))), unlockAt, true);
  }

  function release() external onlyOwner {
    emit Release();
    IveSPA(escrow).withdraw();
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

