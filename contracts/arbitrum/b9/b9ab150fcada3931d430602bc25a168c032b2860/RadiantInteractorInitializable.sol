// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Math.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IAToken.sol";
import "./IVariableDebtToken.sol";
import "./Initializable.sol";

contract RadiantInteractorInitializable is Initializable, ReentrancyGuardUpgradeable {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  bytes32 internal constant _INTERACTOR_UNDERLYING_SLOT = 0x3e9f9f7ea72bae20746fd93eefa9f38d4f124c4ea7b6f6d6641f8cca268c5697;
  bytes32 internal constant _ATOKEN_SLOT = 0x2f43c3ecf8ac46d09de41084e1373bbb359106625ff3f6be5c67006874596c56;
  bytes32 internal constant _LENDING_POOL_SLOT = 0x16629dc35139b48d2fb13a69b9726e401b86938e76df6b9c2ecb3b618e205532;

  constructor() public {
    assert(_INTERACTOR_UNDERLYING_SLOT == bytes32(uint256(keccak256("eip1967.interactorStorage.underlying")) - 1));
    assert(_ATOKEN_SLOT == bytes32(uint256(keccak256("eip1967.interactorStorage.atoken")) - 1));
    assert(_LENDING_POOL_SLOT == bytes32(uint256(keccak256("eip1967.interactorStorage.lendingPool")) - 1));
  }

  function initialize(
    address _underlying,
    address _atoken,
    address _lendingPool
  ) public initializer {
    ReentrancyGuardUpgradeable.initialize();

    _setLendingPool(_lendingPool);
    _setInteractorUnderlying(_underlying);
    _setAToken(_atoken);
  }

  function getBorrowBalance() public view returns(uint256) {
    address _underlying = intUnderlying();
    DataTypes.ReserveData memory reserveData = ILendingPool(lendingPool()).getReserveData(_underlying);
    address debtToken = reserveData.variableDebtTokenAddress;
    uint256 borrowed = IVariableDebtToken(debtToken).balanceOf(address(this));
    return borrowed;
  }

  /**
  * Supplies to Radiant
  */
  function _supply(uint256 amount) internal returns(uint256) {
    address _underlying = intUnderlying();
    address _lendingPool = lendingPool();
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (amount < balance) {
      balance = amount;
    }
    IERC20(_underlying).safeApprove(_lendingPool, 0);
    IERC20(_underlying).safeApprove(_lendingPool, balance);
    ILendingPool(_lendingPool).deposit(_underlying, balance, address(this), 0);
    return balance;
  }

  /**
  * Borrows against the collateral
  */
  function _borrow(uint256 amountUnderlying) internal {
    // Borrow, check the balance for this contract's address
    ILendingPool(lendingPool()).borrow(intUnderlying(), amountUnderlying, 2, 0, address(this));
  }

  /**
  * Repays a loan
  */
  function _repay(uint256 amountUnderlying) internal {
    address _underlying = intUnderlying();
    address _lendingPool = lendingPool();
    IERC20(_underlying).safeApprove(_lendingPool, 0);
    IERC20(_underlying).safeApprove(_lendingPool, amountUnderlying);
    ILendingPool(_lendingPool).repay(_underlying, amountUnderlying, 2, address(this));
  }

  /**
  * Withdraw liquidity in underlying
  */
  function _withdrawUnderlying(uint256 amountUnderlying) internal {
    if (amountUnderlying > 0) {
      ILendingPool(lendingPool()).withdraw(intUnderlying(), amountUnderlying, address(this));
    }
  }

  function redeemMaximumWithLoan(uint256 collateralFactorNumerator, uint256 collateralFactorDenominator) internal {
    address _underlying = intUnderlying();
    address _aToken = aToken();
    // amount of liquidity in Radiant
    uint256 available = IERC20(_underlying).balanceOf(_aToken);
    // amount we supplied
    uint256 supplied = IAToken(_aToken).balanceOf(address(this));
    // amount we borrowed
    uint256 borrowed = getBorrowBalance();
    uint256 balance = supplied.sub(borrowed);

    redeemPartialWithLoan(Math.min(available, balance), 0, collateralFactorNumerator, collateralFactorDenominator);
    supplied = IAToken(_aToken).balanceOf(address(this));
    if (supplied > 0) {
    available = IERC20(_underlying).balanceOf(_aToken);
      _withdrawUnderlying(Math.min(available, supplied));
    }
  }

  function redeemPartialWithLoan(
    uint256 amount,
    uint256 borrowTargetFactorNumerator,
    uint256 collateralFactorNumerator,
    uint256 factorDenominator) internal {

    address _underlying = intUnderlying();
    address _aToken = aToken();
    // amount we supplied
    uint256 supplied = IAToken(_aToken).balanceOf(address(this));
    // amount we borrowed
    uint256 borrowed = getBorrowBalance();
    uint256 newBorrowTarget;
    {
        uint256 oldBalance = supplied.sub(borrowed);
        uint256 newBalance = oldBalance.sub(amount);
        newBorrowTarget = newBalance.mul(borrowTargetFactorNumerator).div(factorDenominator.sub(borrowTargetFactorNumerator));
    }
    while (borrowed > newBorrowTarget) {
      uint256 requiredCollateral = borrowed.mul(factorDenominator).div(collateralFactorNumerator);
      uint256 toRepay = borrowed.sub(newBorrowTarget);
      // redeem just as much as needed to repay the loan
      // supplied - requiredCollateral = max redeemable, amount + repay = needed
      uint256 toRedeem = Math.min(supplied.sub(requiredCollateral), amount.add(toRepay));
      _withdrawUnderlying(toRedeem);
      // now we can repay our borrowed amount
      uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
      _repay(Math.min(toRepay, underlyingBalance));
      // update the parameters
      borrowed = getBorrowBalance();
      supplied = IAToken(_aToken).balanceOf(address(this));
    }
    uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
    if (underlyingBalance < amount) {
      uint256 toRedeem = amount.sub(underlyingBalance);
      uint256 balance = supplied.sub(borrowed);
      // redeem the most we can redeem
      _withdrawUnderlying(Math.min(toRedeem, balance));
    }
  }

  function _setInteractorUnderlying(address _address) internal {
    _setAddress(_INTERACTOR_UNDERLYING_SLOT, _address);
  }

  function intUnderlying() internal virtual view returns (address) {
    return _getAddress(_INTERACTOR_UNDERLYING_SLOT);
  }

  function _setAToken(address _address) internal {
    _setAddress(_ATOKEN_SLOT, _address);
  }

  function aToken() public virtual view returns (address) {
    return _getAddress(_ATOKEN_SLOT);
  }

  function _setLendingPool(address _address) internal {
    _setAddress(_LENDING_POOL_SLOT, _address);
  }

  function lendingPool() public virtual view returns (address) {
    return _getAddress(_LENDING_POOL_SLOT);
  }

  function _setAddress(bytes32 slot, address _address) internal {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      sstore(slot, _address)
    }
  }

  function _getAddress(bytes32 slot) internal view returns (address str) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      str := sload(slot)
    }
  }
}
