// SPDX-License-Identifier: BUSL-1.1
// See bluejay.finance/license
pragma solidity ^0.8.4;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";

import "./ICreditLineBase.sol";

/// @title CreditLineBase
/// @author Bluejay Core Team
/// @notice Base contract for credit line to perform bookeeping of the loan.
/// @dev The child contract should implement the logic to calculate `minPaymentPerPeriod` or
/// override `minPaymentAtTimestamp` for determination of late payments.
abstract contract CreditLineBase is
  ICreditLineBase,
  Initializable,
  OwnableUpgradeable
{
  uint256 constant WAD = 10**18;

  /// @notice Max amount that is allowed to be borrowed, in lending asset decimals
  uint256 public override maxLimit;

  /// @notice Annual interest rate of the loan, in WAD
  uint256 public override interestApr;

  /// @notice Annual interest rate when payment is late, in WAD
  /// Late interest is applied on the principal balance
  uint256 public override lateFeeApr;

  /// @notice Length of time between repayment, in seconds
  /// The first repayment will start at the first period after drawdown happens
  uint256 public override paymentPeriod;

  /// @notice Expected number of periods to repay the loan, in wei
  /// @dev All principal plus balance are due on the end of last period
  uint256 public override loanTenureInPeriods;

  /// @notice Time from a payment period where late interest is not charged, in seconds
  uint256 public override gracePeriod;

  /// @notice Amount of principal balance, in lending asset decimals
  uint256 public override principalBalance;

  /// @notice Amount of interest balance, in lending asset decimals
  /// @dev Does not account for additional interest that has been accrued since the last repayment
  uint256 public override interestBalance;

  /// @notice Cumulative sum of repayment towards principal, in lending asset decimals
  uint256 public override totalPrincipalRepaid;

  /// @notice Cumulative sum of repayment towards interest, in lending asset decimals
  uint256 public override totalInterestRepaid;

  /// @notice Additional repayments made on top of all principal and interest, in lending asset decimals
  /// @dev Additional repayments should be refunded to the borrower
  uint256 public override additionalRepayment;

  /// @notice Cumulative sum of late interest, in lending asset decimals
  /// @dev Value is used to adjust the payment schedule so that the expected repayment
  /// increases to ensure borrower can repay on schedule
  uint256 public override lateInterestAccrued;

  /// @notice Timestamp of the last time interest was accrued and updated, in unix epoch time
  /// @dev Value is always incremented as multiples of the `paymentPeriod`
  uint256 public override interestAccruedAsOf;

  /// @notice Timestamp of the last time full payment was made (ie not late), in unix epoch time
  uint256 public override lastFullPaymentTime;

  /// @notice Minimum amount of payment (principal and/or interest) expected each period, in lending asset decimals
  /// The value is not set until drawdown happens
  /// @dev This can be changed in child contract and/or when a drawdown happens. This is required when using
  /// this base implementation for `minPaymentAtTimestamp`.
  uint256 public override minPaymentPerPeriod;

  /// @notice Timestamp where interest calculation starts, in unix epoch time
  /// @dev This value is set during the drawdown of the loan
  uint256 public override loanStartTime;

  /// @notice State of the loan
  State public override loanState;

  /// @notice Check if the contract is in the correct loan state
  modifier onlyState(State state) {
    if (loanState != state) revert IncorrectState(state, loanState);
    _;
  }

  /// @notice Initialize the contract
  /// @dev Initializing does not immediately start the interest accrual
  /// @param _maxLimit Max amount that is allowed to be borrowed, in lending asset decimals
  /// @param _interestApr Annual interest rate of the loan, in WAD
  /// @param _paymentPeriod Length of time between repayment, in seconds
  /// @param _gracePeriod Time from a payment period where late interest is not charged, in seconds
  /// @param _lateFeeApr Annual interest rate when payment is late, in WAD
  /// @param _loanTenureInPeriods Expected number of periods to repay the loan, in wei
  function initialize(
    uint256 _maxLimit,
    uint256 _interestApr,
    uint256 _paymentPeriod,
    uint256 _gracePeriod,
    uint256 _lateFeeApr,
    uint256 _loanTenureInPeriods
  ) public virtual override initializer {
    __Ownable_init();
    maxLimit = _maxLimit;
    interestApr = _interestApr;
    paymentPeriod = _paymentPeriod;
    gracePeriod = _gracePeriod;
    lateFeeApr = _lateFeeApr;
    loanTenureInPeriods = _loanTenureInPeriods;
    loanState = State.Funding;
    emit LoanStateUpdate(State.Funding);
  }

  // =============================== ADMIN FUNCTIONS =================================

  /// @notice Account for funds received from lenders
  /// @param amount Amount of funds received, in lending asset decimals
  function fund(uint256 amount)
    public
    override
    onlyState(State.Funding)
    onlyOwner
  {
    if (principalBalance + amount > maxLimit) revert MaxLimitExceeded();
    principalBalance += amount;
  }

  /// @notice Drawdown the loan and start interest accrual
  /// @return amount Amount of funds drawn down, in lending asset decimals
  function drawdown()
    public
    override
    onlyState(State.Funding)
    onlyOwner
    returns (uint256 amount)
  {
    loanStartTime = block.timestamp;
    interestAccruedAsOf = block.timestamp;
    lastFullPaymentTime = block.timestamp;
    amount = principalBalance;

    loanState = State.Repayment;
    emit LoanStateUpdate(State.Repayment);

    _afterDrawdown();
  }

  /// @notice Mark the loan as refund state
  /// @dev Child contract should implement the logic to refund the loan
  function refund() public override onlyState(State.Funding) onlyOwner {
    loanState = State.Refund;
    emit LoanStateUpdate(State.Refund);
  }

  /// @notice Make repayment towards the loan
  /// @param amount Amount of repayment, in lending asset decimals
  /// @return interestPayment payment toward interest, in lending asset decimals
  /// @return principalPayment payment toward principal, in lending asset decimals
  /// @return additionalBalancePayment excess repayment, in lending asset decimals
  function repay(uint256 amount)
    public
    override
    onlyOwner
    onlyState(State.Repayment)
    returns (
      uint256 interestPayment,
      uint256 principalPayment,
      uint256 additionalBalancePayment
    )
  {
    // Update accounting variables
    _assess();

    // Apply payment to principal, interest, and additional payments
    (
      interestPayment,
      principalPayment,
      additionalBalancePayment
    ) = allocatePayment(amount, interestBalance, principalBalance);
    principalBalance -= principalPayment;
    interestBalance -= interestPayment;
    totalPrincipalRepaid += principalPayment;
    totalInterestRepaid += interestPayment;
    additionalRepayment += additionalBalancePayment;

    // Update lastFullPaymentTime if payment hits payment schedule
    if (totalPrincipalRepaid + totalInterestRepaid >= minPaymentForSchedule()) {
      lastFullPaymentTime = interestAccruedAsOf;
    }

    // Update state if loan is fully repaid
    if (principalBalance == 0) {
      loanState = State.Repaid;
      emit LoanStateUpdate(State.Repaid);
    }
    emit Repayment(
      block.timestamp,
      amount,
      interestPayment,
      principalPayment,
      additionalBalancePayment
    );
  }

  // =============================== INTERNAL FUNCTIONS =================================

  /// @notice Hook fired after drawdown
  /// @dev To implement logic for adjusting `minPaymentPerPeriod` after drawdown
  /// according to what is actually borrowed vs the max limit in the child contract
  function _afterDrawdown() internal virtual {}

  /// @notice Make adjustments interest and late interest since the last assessment
  function _assess() internal {
    (
      uint256 interestOwed,
      uint256 lateInterestOwed,
      uint256 fullPeriodsElapsed
    ) = interestAccruedSinceLastAssessed();

    // Make accounting adjustments
    interestBalance += interestOwed;
    interestBalance += lateInterestOwed;
    lateInterestAccrued += lateInterestOwed;
    interestAccruedAsOf += fullPeriodsElapsed * paymentPeriod;
  }

  // =============================== VIEW FUNCTIONS =================================

  /// @notice Split a payment into interest, principal, and additional balance
  /// @param amount Amount of payment, in lending asset decimals
  /// @param interestOutstanding Interest balance outstanding, in lending asset decimals
  /// @param principalOutstanding Principal balance outstanding, in lending asset decimals
  /// @return interestPayment payment toward interest, in lending asset decimals
  /// @return principalPayment payment toward principal, in lending asset decimals
  /// @return additionalBalancePayment excess repayment, in lending asset decimals
  function allocatePayment(
    uint256 amount,
    uint256 interestOutstanding,
    uint256 principalOutstanding
  )
    public
    pure
    override
    returns (
      uint256 interestPayment,
      uint256 principalPayment,
      uint256 additionalBalancePayment
    )
  {
    // Allocate to interest first
    interestPayment = amount >= interestOutstanding
      ? interestOutstanding
      : amount;
    amount -= interestPayment;

    // Allocate to principal next
    principalPayment = amount >= principalOutstanding
      ? principalOutstanding
      : amount;
    amount -= principalPayment;

    // Finally apply remaining as additional balance
    additionalBalancePayment = amount;
  }

  /// @notice Calculate the minimum amount of total repayment against the schedule
  /// @return amount Minimum amount, in lending asset decimals
  function minPaymentForSchedule()
    public
    view
    override
    returns (uint256 amount)
  {
    return minPaymentAtTimestamp(block.timestamp);
  }

  /// @notice Calculate the payment due now to avoid further late payment charges
  /// @return amount Payment due, in lending asset decimals
  function paymentDue() public view virtual override returns (uint256 amount) {
    amount = minPaymentAtTimestamp(block.timestamp);

    uint256 periodsElapsed = (block.timestamp - loanStartTime) / paymentPeriod;
    (
      uint256 interestOwed,
      uint256 lateInterestOwed,

    ) = interestAccruedAtTimestamp(block.timestamp);
    amount += lateInterestOwed;
    if (periodsElapsed >= loanTenureInPeriods) {
      // Need to add interest in final payment, since `minPaymentAtTimestamp`
      // assumes the interest has been added
      amount += interestOwed;
    }
    uint256 repaid = totalPrincipalRepaid + totalInterestRepaid;
    if (amount > repaid) {
      amount -= repaid;
    } else {
      amount = 0;
    }
  }

  /// @notice Calculate the minimum amount of total repayment against the schedule
  /// @dev Ensure `interestOwed` and `lateInterestOwed` is already accounted for as a precondition
  /// Child contract can override this to have different payment schedule
  /// @param timestamp Timestamp to calculate the minimum payment, in unix epoch time
  /// @return amount Minimum amount, in lending asset decimals
  function minPaymentAtTimestamp(uint256 timestamp)
    public
    view
    virtual
    override
    returns (uint256 amount)
  {
    if (timestamp <= loanStartTime) return 0;
    if (principalBalance == 0) return 0;
    uint256 periodsElapsed = (timestamp - loanStartTime) / paymentPeriod;
    if (periodsElapsed < loanTenureInPeriods) {
      amount = periodsElapsed * minPaymentPerPeriod + lateInterestAccrued;
    } else {
      amount =
        principalBalance +
        interestBalance +
        totalInterestRepaid +
        totalPrincipalRepaid;
    }
  }

  /// @notice Calculate the interest accrued since the last assessment
  /// @return interestOwed Regular interest accrued, in lending asset decimals
  /// @return lateInterestOwed Late interest accrued, in lending asset decimals
  /// @return fullPeriodsElapsed Number of full periods elapsed
  function interestAccruedSinceLastAssessed()
    public
    view
    override
    returns (
      uint256 interestOwed,
      uint256 lateInterestOwed,
      uint256 fullPeriodsElapsed
    )
  {
    return interestAccruedAtTimestamp(block.timestamp);
  }

  /// @notice Calculate the interest accrued at a given timestamp
  /// @return interestOwed Regular interest accrued, in lending asset decimals
  /// @return lateInterestOwed Late interest accrued, in lending asset decimals
  /// @return fullPeriodsElapsed Number of full periods elapsed
  function interestAccruedAtTimestamp(uint256 timestamp)
    public
    view
    override
    returns (
      uint256 interestOwed,
      uint256 lateInterestOwed,
      uint256 fullPeriodsElapsed
    )
  {
    if (principalBalance == 0) {
      return (interestOwed, lateInterestOwed, fullPeriodsElapsed);
    }
    // Calculate regular interest payments
    fullPeriodsElapsed = (timestamp - interestAccruedAsOf) / paymentPeriod;
    if (fullPeriodsElapsed == 0) {
      return (interestOwed, lateInterestOwed, fullPeriodsElapsed);
    }
    interestOwed += interestOnBalance(fullPeriodsElapsed * paymentPeriod);

    // Calculate late interest payments
    if (timestamp > lastFullPaymentTime + gracePeriod) {
      // Do not apply grace period, if last full payment was before period start
      uint256 latePeriodsElapsed = (
        lastFullPaymentTime < interestAccruedAsOf
          ? (timestamp - interestAccruedAsOf)
          : (timestamp - interestAccruedAsOf - gracePeriod)
      ) / paymentPeriod;
      lateInterestOwed += lateInterestOnBalance(
        latePeriodsElapsed * paymentPeriod
      );
    }
  }

  /// @notice Calculate the regular interest accrued on the principal balance
  /// @param period Period to calculate interest on, in seconds
  /// @return interestOwed Regular interest accrued, in lending asset decimals
  function interestOnBalance(uint256 period)
    public
    view
    override
    returns (uint256 interestOwed)
  {
    return (principalBalance * interestApr * period) / (365 days * WAD);
  }

  /// @notice Calculate the late interest accrued on the principal balance
  /// @param period Period to calculate interest on, in seconds
  /// @return interestOwed Late interest accrued, in lending asset decimals
  function lateInterestOnBalance(uint256 period)
    public
    view
    override
    returns (uint256 interestOwed)
  {
    return (principalBalance * lateFeeApr * period) / (365 days * WAD);
  }

  /// @notice Get the sum of all repayments made
  /// @return amount Total repayment, in lending asset decimals
  function totalRepayments() public view override returns (uint256 amount) {
    amount = totalPrincipalRepaid + totalInterestRepaid;
  }
}

