// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./ICollateral.sol";
import "./IHook.sol";
import "./SafeAccessControlEnumerableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";

contract Collateral is
  ICollateral,
  ERC20PermitUpgradeable,
  ReentrancyGuardUpgradeable,
  SafeAccessControlEnumerableUpgradeable
{
  IERC20 private immutable _baseToken;
  uint256 private immutable _baseTokenDenominator;
  uint256 private _depositFee;
  uint256 private _withdrawFee;
  IHook private _depositHook;
  IHook private _withdrawHook;

  uint256 public constant override PERCENT_DENOMINATOR = 1000000;
  uint256 public constant override FEE_LIMIT = 100000;
  bytes32 public constant override SET_DEPOSIT_FEE_ROLE =
    keccak256("setDepositFee");
  bytes32 public constant override SET_WITHDRAW_FEE_ROLE =
    keccak256("setWithdrawFee");
  bytes32 public constant override SET_DEPOSIT_HOOK_ROLE =
    keccak256("setDepositHook");
  bytes32 public constant override SET_WITHDRAW_HOOK_ROLE =
    keccak256("setWithdrawHook");

  constructor(IERC20 baseToken, uint256 baseTokenDecimals) {
    _baseToken = baseToken;
    _baseTokenDenominator = 10**baseTokenDecimals;
  }

  function initialize(string memory name, string memory symbol)
    public
    initializer
  {
    __SafeAccessControlEnumerable_init();
    __ERC20_init(name, symbol);
    __ERC20Permit_init(name);
    __ReentrancyGuard_init();
  }

  /**
   * @dev If hook not set, fees remain within the contract as extra reserves
   * (withdrawable by manager). Converts amount after fee from base token
   * units to collateral token units.
   */
  function deposit(address recipient, uint256 baseTokenAmount)
    external
    override
    nonReentrant
    returns (uint256 collateralMintAmount)
  {
    uint256 fee = (baseTokenAmount * _depositFee) / PERCENT_DENOMINATOR;
    if (_depositFee > 0) {
      require(fee > 0, "fee = 0");
    } else {
      require(baseTokenAmount > 0, "base token amount = 0");
    }
    _baseToken.transferFrom(msg.sender, address(this), baseTokenAmount);
    uint256 baseTokenAmountAfterFee = baseTokenAmount - fee;
    if (address(_depositHook) != address(0)) {
      _baseToken.approve(address(_depositHook), fee);
      _depositHook.hook(
        msg.sender,
        recipient,
        baseTokenAmount,
        baseTokenAmountAfterFee
      );
      _baseToken.approve(address(_depositHook), 0);
    }
    collateralMintAmount =
      (baseTokenAmountAfterFee * 1e18) /
      _baseTokenDenominator;
    _mint(recipient, collateralMintAmount);
    emit Deposit(recipient, baseTokenAmountAfterFee, fee);
  }

  function withdraw(address recipient, uint256 collateralAmount)
    external
    override
    nonReentrant
    returns (uint256 baseTokenAmountAfterFee)
  {
    uint256 baseTokenAmount = (collateralAmount * _baseTokenDenominator) /
      1e18;
    uint256 fee = (baseTokenAmount * _withdrawFee) / PERCENT_DENOMINATOR;
    if (_withdrawFee > 0) {
      require(fee > 0, "fee = 0");
    } else {
      require(baseTokenAmount > 0, "base token amount = 0");
    }
    _burn(msg.sender, collateralAmount);
    baseTokenAmountAfterFee = baseTokenAmount - fee;
    if (address(_withdrawHook) != address(0)) {
      _baseToken.approve(address(_withdrawHook), fee);
      _withdrawHook.hook(
        msg.sender,
        recipient,
        baseTokenAmount,
        baseTokenAmountAfterFee
      );
      _baseToken.approve(address(_withdrawHook), 0);
    }
    _baseToken.transfer(recipient, baseTokenAmountAfterFee);
    emit Withdraw(msg.sender, recipient, baseTokenAmountAfterFee, fee);
  }

  function setDepositFee(uint256 depositFee)
    external
    override
    onlyRole(SET_DEPOSIT_FEE_ROLE)
  {
    require(depositFee <= FEE_LIMIT, "Exceeds fee limit");
    _depositFee = depositFee;
    emit DepositFeeChange(depositFee);
  }

  function setWithdrawFee(uint256 withdrawFee)
    external
    override
    onlyRole(SET_WITHDRAW_FEE_ROLE)
  {
    require(withdrawFee <= FEE_LIMIT, "Exceeds fee limit");
    _withdrawFee = withdrawFee;
    emit WithdrawFeeChange(withdrawFee);
  }

  function setDepositHook(IHook depositHook)
    external
    override
    onlyRole(SET_DEPOSIT_HOOK_ROLE)
  {
    _depositHook = depositHook;
    emit DepositHookChange(address(depositHook));
  }

  function setWithdrawHook(IHook withdrawHook)
    external
    override
    onlyRole(SET_WITHDRAW_HOOK_ROLE)
  {
    _withdrawHook = withdrawHook;
    emit WithdrawHookChange(address(withdrawHook));
  }

  function getBaseToken() external view override returns (IERC20) {
    return _baseToken;
  }

  function getDepositFee() external view override returns (uint256) {
    return _depositFee;
  }

  function getWithdrawFee() external view override returns (uint256) {
    return _withdrawFee;
  }

  function getDepositHook() external view override returns (IHook) {
    return _depositHook;
  }

  function getWithdrawHook() external view override returns (IHook) {
    return _withdrawHook;
  }

  function getBaseTokenBalance() external view override returns (uint256) {
    return _baseToken.balanceOf(address(this));
  }
}

