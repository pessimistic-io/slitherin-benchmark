// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {MathUpgradeable} from "./MathUpgradeable.sol";
import {SafeERC20Upgradeable} from "./SafeERC20Upgradeable.sol";
import {IERC20PermitUpgradeable} from "./draft-IERC20PermitUpgradeable.sol";
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {PoolBaseInfo} from "./PoolBaseInfo.sol";
import {Decimal} from "./Decimal.sol";
import {IAuction} from "./IAuction.sol";

error NEL(uint256 available);
error OG();
error OM();
error OA();
error OF();
error AZ();
error MTB(uint256 borrowed, uint256 repay);

error CDC();

/// @notice This contract describes basic logic of the Pool - everything related to borrowing
abstract contract PoolBase is PoolBaseInfo {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using Decimal for uint256;

  // MODIFIERS

  /// @notice Modifier to accrue interest and check that pool is currently active (possibly in warning)
  modifier onlyActiveAccrual() {
    _accrueInterest();
    State currentState = _state(_info);
    require(
      currentState == State.Active ||
        currentState == State.Warning ||
        currentState == State.ProvisionalDefault,
      "PIA"
    );
    _;
  }

  /// @notice Modifier for functions restricted to manager
  modifier onlyManager() {
    if (msg.sender != manager) revert OM();
    _;
  }

  /// @notice Modifier for functions restricted to protocol governor
  modifier onlyGovernor() {
    if (msg.sender != factory.owner()) revert OG();
    _;
  }

  /// @notice Modifier for functions restricted to auction contract
  modifier onlyAuction() {
    if (msg.sender != factory.auction()) revert OA();
    _;
  }

  /// @notice Modifier for the functions restricted to factory
  modifier onlyFactory() {
    if (msg.sender != address(factory)) revert OF();
    _;
  }

  modifier onlyEligible(address lender) {
    _getKYCAttributes(lender);
    _;
  }

  // PUBLIC FUNCTIONS

  /// @notice Function is used to provide liquidity for Pool in exchange for cpTokens
  /// @dev Approval for desired amount of currency token should be given in prior
  /// @param currencyAmount Amount of currency token that user want to provide
  function provide(uint256 currencyAmount) external onlyEligible(msg.sender) {
    _provide(currencyAmount, msg.sender);
  }

  /// @notice Function is used to provide liquidity in exchange for cpTokens to the given address
  /// @dev Approval for desired amount of currency token should be given in prior
  /// @param currencyAmount Amount of currency token that user want to provide
  /// @param receiver Receiver of cpTokens
  function provideFor(uint256 currencyAmount, address receiver) external onlyEligible(receiver) {
    _provide(currencyAmount, receiver);
  }

  /// @notice Function is used to provide liquidity in exchange for cpTokens, using EIP2612 off-chain signed permit for currency
  /// @param currencyAmount Amount of currency token that user want to provide
  /// @param deadline Deadline for EIP2612 approval
  /// @param v V component of permit signature
  /// @param r R component of permit signature
  /// @param s S component of permit signature
  function provideWithPermit(
    uint256 currencyAmount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external onlyEligible(msg.sender) {
    IERC20PermitUpgradeable(address(currency)).permit(
      msg.sender,
      address(this),
      currencyAmount,
      deadline,
      v,
      r,
      s
    );
    _provide(currencyAmount, msg.sender);
  }

  /// @notice Function is used to provide liquidity for Pool in exchange for cpTokens to given address, using EIP2612 off-chain signed permit for currency
  /// @param currencyAmount Amount of currency token that user want to provide
  /// @param receiver Receiver of cpTokens
  /// @param deadline Deadline for EIP2612 approval
  /// @param v V component of permit signature
  /// @param r R component of permit signature
  /// @param s S component of permit signature
  function provideForWithPermit(
    uint256 currencyAmount,
    address receiver,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external onlyEligible(receiver) {
    IERC20PermitUpgradeable(address(currency)).permit(
      msg.sender,
      address(this),
      currencyAmount,
      deadline,
      v,
      r,
      s
    );
    _provide(currencyAmount, receiver);
  }

  /// @notice Function is used to redeem previously provided liquidity with interest, burning cpTokens
  /// @param tokens Amount of cpTokens to burn (MaxUint256 to burn maximal possible)
  function redeem(uint256 tokens) external onlyEligible(msg.sender) {
    _accrueInterest();
    uint256 exchangeRate = _storedExchangeRate();
    uint256 currencyAmount;

    if (tokens == type(uint256).max) {
      (tokens, currencyAmount) = _maxWithdrawable(exchangeRate);
    } else {
      currencyAmount = tokens.mulDecimal(exchangeRate);
    }

    _redeem(tokens, currencyAmount);
  }

  /// @notice Function is used to redeem previously provided liquidity with interest, burning cpTokens
  /// @param currencyAmount Amount of currency to redeem (MaxUint256 to redeem maximal possible)
  function redeemCurrency(uint256 currencyAmount) external onlyEligible(msg.sender) {
    _accrueInterest();

    uint256 exchangeRate = _storedExchangeRate();
    uint256 tokens;
    if (currencyAmount == type(uint256).max) {
      (tokens, currencyAmount) = _maxWithdrawable(exchangeRate);
    } else {
      tokens = currencyAmount.divDecimal(exchangeRate);
    }
    _redeem(tokens, currencyAmount);
  }

  /// @notice Function is used to borrow from the pool
  /// @param amount Amount of currency to borrow (MaxUint256 to borrow everything available)
  /// @param receiver Address where to transfer currency
  function borrow(uint256 amount, address receiver) external onlyManager onlyActiveAccrual {
    uint256 available = _availableToBorrow(_info);
    if (amount == 0) revert AZ();
    if (amount == type(uint256).max) {
      amount = available;
    } else if (amount > available) {
      revert NEL(available);
    }

    _info.principal += amount;
    _info.borrows += amount;
    _transferOut(receiver, amount);

    _checkUtilization();

    emit Borrowed(amount, receiver);
  }

  /// @notice Function is used to repay borrowed funds
  /// @dev Manager can close the pool if all debt is repaid
  /// @param amount Amount to repay (MaxUint256 to repay all debt)
  function repay(uint256 amount) external onlyManager onlyActiveAccrual {
    uint256 borrows = _info.borrows;
    if (amount == type(uint256).max) {
      amount = borrows;
    } else {
      // require(amount <= _info.borrows, "MTB");
      if (amount > borrows) revert MTB(amount, borrows);
    }

    _transferIn(msg.sender, amount);

    if (amount > borrows - _info.principal) {
      _info.principal = borrows - amount;
    }
    _info.borrows -= amount;

    _checkUtilization();

    emit Repaid(amount);
  }

  /// @notice Function is used to close pool
  /// @dev Governor can close the pool at anytime
  /// @dev Pool closes after auction ends by `processDebtClaim()` function

  function close() external {
    _accrueInterest();
    /// @dev Link to governor address
    address governor = factory.owner();

    bool governorClosing = msg.sender == governor;

    require(governorClosing, "SCC");
    _close();
  }

  /// @notice Function is used to distribute insurance and close pool after period to start auction passed
  /// @dev If pool is defaulting, auction is not started and period to start auction passed, anyone can close the pool
  function allowWithdrawalAfterNoAuction() external {
    _accrueInterest();

    /// @dev Check if pool is defaulting
    bool isDefaulting = _state(_info) == State.Default;
    /// @dev Check if auction is not started
    bool auctionNotStarted = IAuction(factory.auction()).state(address(this)) ==
      IAuction.State.NotStarted;
    /// @dev Check if auction can't be started now since [last accrual + period to start auction]
    bool periodToStartPassed = block.timestamp >= _info.lastAccrual + periodToStartAuction;
    /// @dev If all conditions are met, pool can be closed
    if (isDefaulting && auctionNotStarted && periodToStartPassed) {
      _info.insurance = 0;
      debtClaimed = true;
    } else {
      revert CDC();
    }
  }

  /// @notice Function is called by governor to transfer reserves to the treasury
  function transferReserves() external onlyGovernor {
    _accrueInterest();
    _transferReserves();
  }

  /// @notice Function used to account older reserve transfers via emitting event
  /// @param to Recipient of older reserve transfers
  /// @param amount Amount of reserves transferred before
  function accountOlderReserveTransfers(address to, uint256 amount) external onlyGovernor {
    emit ReservesTransferred(to, amount);
  }

  /// @notice Function is called by governor to force pool default (in case of default in other chain)
  function forceDefault() external onlyGovernor onlyActiveAccrual {
    _info.state = State.Default;
  }

  /// @notice Function is called by Auction contract when auction is started
  function processAuctionStart() external onlyAuction {
    _accrueInterest();
    _transferReserves();
    factory.burnStake();
  }

  /// @notice Function is called by Auction contract to process pool debt claim
  /// @dev Closes pool after auction ends, regardless of auction result
  function processDebtClaim() external onlyAuction {
    _accrueInterest();
    _info.state = State.Default;
    address debtOwner = ownerOfDebt();

    if (_info.insurance > 0 && debtOwner != address(0)) {
      _transferOut(debtOwner, _info.insurance);
    }
    _info.insurance = 0;
    debtClaimed = true;
    _close();
  }

  // INTERNAL FUNCTIONS

  /// @notice Internal function that processes providing liquidity for Pool in exchange for cpTokens
  /// @param currencyAmount Amount of currency token that user want to provide
  /// @param receiver Receiver of cpTokens
  function _provide(uint256 currencyAmount, address receiver) internal onlyActiveAccrual {
    _handleMaxCapacity(currencyAmount);

    uint256 exchangeRate = _storedExchangeRate();
    _transferIn(msg.sender, currencyAmount);
    uint256 tokens = currencyAmount.divDecimal(exchangeRate);
    _mint(receiver, tokens);
    _checkUtilization();

    emit Provided(receiver, currencyAmount, tokens);
  }

  /// @notice Internal function that processes token redemption
  /// @param tokensAmount Amount of tokens being redeemed
  /// @param currencyAmount Equivalent amount of currency
  function _redeem(uint256 tokensAmount, uint256 currencyAmount) internal {
    if (debtClaimed) {
      require(currencyAmount <= cash(), "NEC");
    } else {
      require(
        currencyAmount <= _availableToProviders(_info) &&
          currencyAmount <= _availableProvisionalDefault(_info),
        "NEC"
      );
    }

    _burn(msg.sender, tokensAmount);
    _transferOut(msg.sender, currencyAmount);
    if (!debtClaimed) {
      _checkUtilization();
    }

    emit Redeemed(msg.sender, currencyAmount, tokensAmount);
  }

  /// @notice Internal function to transfer reserves to the treasury
  function _transferReserves() internal {
    address treasury = factory.treasury();
    uint256 reserves = _info.reserves;

    _transferOut(treasury, reserves);
    _info.reserves = 0;

    emit ReservesTransferred(treasury, reserves);
  }

  /// @notice Internal function for closing pool
  function _close() internal {
    require(_info.state != State.Closed, "PIC");

    _info.state = State.Closed;
    _transferReserves();
    if (_info.insurance > 0) {
      _transferOut(factory.treasury(), _info.insurance);
      _info.insurance = 0;
    }
    factory.closePool();
    emit Closed();
  }

  /// @notice Internal function to accrue interest
  function _accrueInterest() internal {
    _info = _accrueInterestVirtual();
  }

  /// @notice Internal function that is called at each action to check for zero/warning/default utilization
  function _checkUtilization() internal {
    if (_info.borrows == 0) {
      _info.enteredProvisionalDefault = 0;
      if (_info.enteredZeroUtilization == 0) {
        _info.enteredZeroUtilization = block.timestamp;
      }
      return;
    }

    _info.enteredZeroUtilization = 0;

    if (_info.enteredProvisionalDefault != 0) {
      // user entered provisional default
      if (_utilizationIsBelowProvisionalRepayment()) {
        _info.enteredProvisionalDefault = 0;
      }
    } else {
      // user may or may not enter the provisional default
      if (_info.borrows >= _poolSize(_info).mulDecimal(provisionalDefaultUtilization)) {
        _info.enteredProvisionalDefault = block.timestamp;
      }
    }
  }

  /// @notice Internal function used for transfers of currency from given account to contract
  /// @param from Address to transfer from
  /// @param amount Amount to transfer
  function _transferIn(address from, uint256 amount) internal virtual {
    currency.safeTransferFrom(from, address(this), amount);
  }

  /// @notice Internal function used for transfers of currency to given account from contract
  /// @param to Address to transfer to
  /// @param amount Amount to transfer
  function _transferOut(address to, uint256 amount) internal virtual {
    currency.safeTransfer(to, amount);
  }

  // PUBLIC VIEW

  /// @notice Function to get owner of the pool's debt
  /// @return Pool's debt owner
  function ownerOfDebt() public view returns (address) {
    return IAuction(factory.auction()).ownerOfDebt(address(this));
  }

  /// @notice Function returns cash amount (balance of currency in the pool)
  /// @return Cash amount
  function cash() public view virtual returns (uint256) {
    return currency.balanceOf(address(this));
  }

  // INTERNAL VIEW

  /// @notice Function to get current pool state
  /// @return Pool state as State enumerable
  function _state(BorrowInfo memory info) internal view returns (State) {
    if (info.state == State.Closed || info.state == State.Default) {
      return info.state;
    }
    if (info.enteredProvisionalDefault != 0) {
      if (block.timestamp >= info.enteredProvisionalDefault + warningGracePeriod) {
        return State.Default;
      } else {
        return State.ProvisionalDefault;
      }
    }
    if (info.borrows > 0 && info.borrows >= _poolSize(info).mulDecimal(warningUtilization)) {
      return State.Warning;
    }
    return info.state;
  }

  /// @notice Function returns interest value for given borrow info
  /// @param info Borrow info struct
  /// @return Interest for given info
  function _interest(BorrowInfo memory info) internal pure returns (uint256) {
    return info.borrows - info.principal;
  }

  /// @notice Function returns amount of funds generally available for providers value for given borrow info
  /// @param info Borrow info struct
  /// @return Available to providers for given info
  function _availableToProviders(BorrowInfo memory info) internal view returns (uint256) {
    return cash() - info.reserves - info.insurance;
  }

  /// @notice Function returns available to borrow value for given borrow info
  /// @param info Borrow info struct
  /// @return Available to borrow for given info
  function _availableToBorrow(BorrowInfo memory info) internal view returns (uint256) {
    uint256 basicAvailable = _availableToProviders(info) - _interest(info);
    uint256 borrowsForWarning = _poolSize(info).mulDecimal(warningUtilization);
    if (borrowsForWarning > info.borrows) {
      return MathUpgradeable.min(borrowsForWarning - info.borrows, basicAvailable);
    } else {
      return 0;
    }
  }

  /// @notice Function returns pool size for given borrow info
  /// @param info Borrow info struct
  /// @return Pool size for given info
  function _poolSize(BorrowInfo memory info) internal view returns (uint256) {
    return _availableToProviders(info) + info.principal;
  }

  /// @notice Function returns funds available to be taken from pool before provisional default will be reached
  /// @param info Borrow info struct
  /// @return Pool size for given info
  function _availableProvisionalDefault(BorrowInfo memory info) internal view returns (uint256) {
    if (provisionalDefaultUtilization == 0) {
      return 0;
    }
    uint256 poolSizeForProvisionalDefault = info.borrows.divDecimal(provisionalDefaultUtilization);
    uint256 currentPoolSize = _poolSize(info);
    return
      currentPoolSize > poolSizeForProvisionalDefault
        ? currentPoolSize - poolSizeForProvisionalDefault
        : 0;
  }

  /// @notice Function returns maximal redeemable amount for given exchange rate
  /// @param exchangeRate Exchange rate of cp-tokens to currency
  /// @return tokensAmount Maximal redeemable amount of pool tokens
  /// @return currencyAmount Maximal redeemable amount of currency tokens
  function _maxWithdrawable(
    uint256 exchangeRate
  ) internal view returns (uint256 tokensAmount, uint256 currencyAmount) {
    currencyAmount = _availableToProviders(_info); /// [total currency balance] - reserves - insurance

    if (!debtClaimed) {
      uint256 availableProvisionalDefault = _availableProvisionalDefault(_info);
      if (availableProvisionalDefault < currencyAmount) {
        currencyAmount = availableProvisionalDefault;
      }
    }
    tokensAmount = currencyAmount.divDecimal(exchangeRate);

    if (balanceOf(msg.sender) < tokensAmount) {
      tokensAmount = balanceOf(msg.sender);
      currencyAmount = tokensAmount.mulDecimal(exchangeRate);
    }
  }

  /// @notice Function returns stored (without accruing) exchange rate of cpTokens for currency tokens
  /// @return Stored exchange rate as 10-digits decimal
  function _storedExchangeRate() internal view returns (uint256) {
    if (totalSupply() == 0) {
      return Decimal.ONE;
    } else if (debtClaimed) {
      return cash().divDecimal(totalSupply());
    } else {
      return (_availableToProviders(_info) + _info.borrows).divDecimal(totalSupply());
    }
  }

  /// @notice Function returns timestamp when pool entered or will enter provisional default at given interest rate
  /// @param interestRate Borrows interest rate at current period
  /// @return Timestamp of entering provisional default (0 if won't ever enter)
  function _entranceOfProvisionalDefault(uint256 interestRate) internal view returns (uint256) {
    /// @dev If pool is already in provisional default, return its timestamp
    if (_info.enteredProvisionalDefault != 0) {
      return _info.enteredProvisionalDefault;
    }
    if (_info.borrows == 0 || interestRate == 0) {
      return 0;
    }

    // Consider:
    // IFPD - Interest for provisional default
    // PSPD = Pool size at provisional default
    // IRPD = Reserves & insurance at provisional default
    // IR = Current reserves and insurance
    // PDU = Provisional default utilization
    // We have: Borrows + IFPD = PDU * PSPD
    // => Borrows + IFPD = PDU * (Principal + Cash + IRPD)
    // => Borrows + IFPD = PDU * (Principal + Cash + IR + IFPD * (insuranceFactor + reserveFactor))
    // => IFPD * (1 + PDU * (reserveFactor + insuranceFactor)) = PDU * PoolSize - Borrows
    // => IFPD = (PDU * PoolSize - Borrows) / (1 + PDU * (reserveFactor + insuranceFactor))
    uint256 numerator = _poolSize(_info).mulDecimal(provisionalDefaultUtilization) - _info.borrows;
    uint256 denominator = Decimal.ONE +
      provisionalDefaultUtilization.mulDecimal(reserveFactor + insuranceFactor);
    uint256 interestForProvisionalDefault = numerator.divDecimal(denominator);

    uint256 interestPerSec = _info.borrows * interestRate;
    // Time delta is calculated as interest for provisional default divided by interest per sec (rounded up)
    uint256 timeDelta = (interestForProvisionalDefault * Decimal.ONE + interestPerSec - 1) /
      interestPerSec;
    uint256 entrance = _info.lastAccrual + timeDelta;
    return entrance <= block.timestamp ? entrance : 0;
  }

  /// @notice Function virtually accrues interest and returns updated borrow info struct
  /// @return newInfo borrow info struct after accrual
  function _accrueInterestVirtual() internal view returns (BorrowInfo memory newInfo) {
    /// @dev Read info from storage to memory
    newInfo = _info;

    /// @dev If last accrual was at current block or pool is closed or in default, return info as is
    if (
      block.timestamp == newInfo.lastAccrual ||
      newInfo.state == State.Default ||
      newInfo.state == State.Closed
    ) {
      return newInfo;
    }

    /// @dev Get interest rate according to interest rate model
    uint256 interestRate = interestRateModel.getBorrowRate(
      cash(),
      newInfo.borrows,
      newInfo.reserves + newInfo.insurance + _interest(newInfo)
    );

    newInfo.lastAccrual = block.timestamp;
    newInfo.enteredProvisionalDefault = _entranceOfProvisionalDefault(interestRate);
    if (
      newInfo.enteredProvisionalDefault != 0 &&
      newInfo.enteredProvisionalDefault + warningGracePeriod < newInfo.lastAccrual
    ) {
      newInfo.lastAccrual = newInfo.enteredProvisionalDefault + warningGracePeriod;
    }
    /// @dev Interest dealta == borrows * interest rate * time delta
    uint256 interestDelta = newInfo.borrows.mulDecimal(
      interestRate * (newInfo.lastAccrual - _info.lastAccrual)
    );
    uint256 reservesDelta = interestDelta.mulDecimal(reserveFactor);
    uint256 insuranceDelta = interestDelta.mulDecimal(insuranceFactor);

    if (newInfo.borrows + interestDelta + reservesDelta + insuranceDelta > _poolSize(newInfo)) {
      interestDelta = (_poolSize(newInfo) - newInfo.borrows).divDecimal(
        Decimal.ONE + reserveFactor + insuranceFactor
      );
      uint256 interestPerSec = newInfo.borrows.mulDecimal(interestRate);
      if (interestPerSec > 0) {
        // Previous last accrual plus interest divided by interest speed (rounded up)
        newInfo.lastAccrual =
          _info.lastAccrual +
          (interestDelta + interestPerSec - 1) /
          interestPerSec;
      }

      reservesDelta = interestDelta.mulDecimal(reserveFactor);
      insuranceDelta = interestDelta.mulDecimal(insuranceFactor);
      newInfo.state = State.Default;
    }

    newInfo.borrows += interestDelta;
    newInfo.reserves += reservesDelta;
    newInfo.insurance += insuranceDelta;

    return newInfo;
  }

  function _handleMaxCapacity(uint256 amount) internal view virtual;

  function _getKYCAttributes(address lender) internal virtual;

  function _utilizationIsBelowProvisionalRepayment() internal view virtual returns (bool);
}

