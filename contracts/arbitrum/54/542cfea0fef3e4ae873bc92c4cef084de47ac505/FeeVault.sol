// SPDX-License-Identifier: BUSL-1.1

import "./ITimeLock.sol";
import "./ERC20Fixed.sol";
import "./FixedPoint.sol";
import {LiquidityPool} from "./LiquidityPool.sol";
import {ERC20} from "./ERC20.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";

pragma solidity ^0.8.17;

contract FeeVault is OwnableUpgradeable, AccessControlUpgradeable {
  using FixedPoint for uint256;
  using ERC20Fixed for ERC20;
  using ERC20Fixed for LiquidityPool;

  bytes32 public constant APPROVED_ROLE = keccak256("APPROVED_ROLE");

  address public baseToken;
  address public liquidityPool;
  uint256 public balance;

  ITimeLock public timeLock;
  uint256 public timeLockThreshold;

  event AddBalanceEvent(address claimer, uint256 amount);
  event RemoveBalanceEvent(address claimer, uint256 amount);
  event SetTimeLockEvent(ITimeLock timeLock);
  event SetTimeLockThresholdEvent(uint256 timeLockThreshold);

  function initialize(
    address _owner,
    address _baseToken,
    address _liquidityPool
  ) external initializer {
    __Ownable_init();
    __AccessControl_init();

    _transferOwnership(_owner);
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);

    baseToken = _baseToken;
    liquidityPool = _liquidityPool;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function setTimeLockThreshold(uint256 _timeLockThreshold) external onlyOwner {
    timeLockThreshold = _timeLockThreshold;
    emit SetTimeLockThresholdEvent(timeLockThreshold);
  }

  function setTimeLock(ITimeLock _timeLock) external onlyOwner {
    timeLock = _timeLock;
    emit SetTimeLockEvent(timeLock);
  }

  function add(uint256 amount) external {
    _require(amount > 0, Errors.INVALID_AMOUNT);

    ERC20(baseToken).transferFromFixed(msg.sender, address(this), amount);
    ERC20(baseToken).approve(liquidityPool, amount);
    LiquidityPool(liquidityPool).mint(amount);
    uint256 minted = LiquidityPool(liquidityPool).balanceOfFixed(address(this));
    LiquidityPool(liquidityPool).approve(liquidityPool, minted);
    LiquidityPool(liquidityPool).stake(minted);
    balance += minted;
  }

  function redeem(address to, uint256 amount) external onlyRole(APPROVED_ROLE) {
    LiquidityPool(liquidityPool).unstake(amount);
    LiquidityPool(liquidityPool).burn(amount);
    uint256 burnt = ERC20(baseToken).balanceOfFixed(address(this));

    if (burnt >= timeLockThreshold) {
      ERC20(baseToken).approveFixed(address(timeLock), burnt);
      timeLock.createAgreement(
        address(baseToken),
        burnt,
        to,
        TimeLockDataTypes.AgreementContext.FEE_VAULT
      );
    } else {
      ERC20(baseToken).transferFixed(to, burnt);
    }
  }
}

