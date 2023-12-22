// SPDX-License-Identifier: MIT
// Metadrop Contracts (v0.0.1)

/**
 *
 * @title PrimaryVestingByMetadrop.sol. This contract is the primary sale proceeds vesting contract
 * from the metadrop deployment platform
 *
 * It performs vesting of project funds (if configured) and splits payments between the project team
 * and the platform
 *
 * Primary vesting looks to address the disconnect between primary sales volume and the
 * need for project teams to continue to deliver value to holders.
 * Note this contract is both a vesting contract and payment splitter, allowing disbursement
 * of funds to n parties with vesting for each
 * Note based on OpenZeppelin contracts but modified to a) combine vesting and payment split and
 * b) allow this contract to be cloned, i.e. set state initialise not in the constructor.
 *
 * @author metadrop https://metadrop.com/
 *
 */

pragma solidity 0.8.19;

import "./Context.sol";
import "./SafeERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import "./Address.sol";
import "./IPrimaryVestingByMetadrop.sol";
import {IWETH} from "./IWETH.sol";

contract PrimaryVestingByMetadrop is Context, IPrimaryVestingByMetadrop {
  using SafeERC20 for IERC20;

  // Default for any percentages, which must be held as basis points, i.e. 5% is 500
  uint256 constant PERCENTAGE_DENOMINATOR = 10000; //10,000 i.e. 100.00

  IWETH public immutable weth;

  // Beneficiary addresses
  address payable private _platformAddress;

  // Shares
  uint256 private _totalShares;
  uint256 private _platformShare;
  uint256 private _projectUpfrontShare;
  uint256 private _projectVestedShare;

  // Project share splits: project allocation ce be split amoung n addresses:
  uint256 private _totalProjectShares;
  ProjectBeneficiary[] private _projectBeneficiaries;

  // ETH Release tracking
  uint256 private _totalETHReleased;
  uint256 private _platformETHReleased;
  uint256 private _projectUpFrontETHReleased;
  uint256 private _projectVestedETHReleased;

  // ERC20 Release tracking
  mapping(IERC20 => uint256) private _erc20TotalReleased;
  mapping(IERC20 => uint256) private _platformERC20Released;
  mapping(IERC20 => uint256) private _projectUpfrontERC20Released;
  mapping(IERC20 => uint256) private _projectVestedERC20Released;

  // Vesting details
  uint256 private _vestingStart;
  uint256 private _vestingCliff;
  uint256 private _vestingPeriod;

  // Bool that controls initialisation and only allows it to occur ONCE. This is
  // needed as this contract is clonable, threfore the constructor is not called
  // on cloned instances. We setup state of this contract through the initialise
  // function.
  bool initialised;

  /** ====================================================================================================================
   *                                              CONSTRUCTOR AND INTIIALISE
   * =====================================================================================================================
   */
  /** ____________________________________________________________________________________________________________________
   *                                                                                                        -->CONSTRUCTOR
   * @dev constructor           The constructor is not called when the contract is cloned. In this
   *                            constructor we just setup default values and set the template contract to initialised.
   * _____________________________________________________________________________________________________________________
   */
  constructor(address wethAddress_) {
    initialised = true;
    weth = IWETH(wethAddress_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                         -->INITIALISE
   * @dev (function) initialisePrimaryVesting  Initialise data on the vesting contract
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vestingModule_    Configuration object for this instance of vesting
   * ---------------------------------------------------------------------------------------------------------------------
   * @param platformAddress_  The address for payments to the platform
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function initialisePrimaryVesting(
    VestingModuleConfig calldata vestingModule_,
    address platformAddress_,
    uint256 platformShare_
  ) external {
    if (initialised) revert AlreadyInitialised();

    // Decode the config:
    VestingConfig memory vestingConfig = abi.decode(
      vestingModule_.configData,
      (VestingConfig)
    );

    require(platformAddress_ != address(0), "Platform payee required");

    require(
      (vestingConfig.projectUpFrontShare + vestingConfig.projectVestedShare) ==
        PERCENTAGE_DENOMINATOR,
      "Upfront plus vested share must equal 10,000"
    );

    // Set beneficiary addresses:
    _platformAddress = payable(platformAddress_);

    // Add the project beneficiaries:
    for (uint256 i = 0; i < vestingConfig.projectPayees.length; ) {
      _projectBeneficiaries.push(vestingConfig.projectPayees[i]);
      _totalProjectShares += vestingConfig.projectPayees[i].payeeShares;

      unchecked {
        i++;
      }
    }

    require(_totalProjectShares != 0, "Project share total cannot be 0");

    // Set beneficiary shares:
    _platformShare = platformShare_;

    _projectUpfrontShare =
      ((PERCENTAGE_DENOMINATOR - _platformShare) *
        vestingConfig.projectUpFrontShare) /
      PERCENTAGE_DENOMINATOR;
    _projectVestedShare =
      ((PERCENTAGE_DENOMINATOR - _platformShare) *
        vestingConfig.projectVestedShare) /
      PERCENTAGE_DENOMINATOR;

    _totalShares = _platformShare + _projectUpfrontShare + _projectVestedShare;

    // Set vesting details:
    _vestingPeriod = vestingConfig.vestingPeriodInDays * 1 days;
    _vestingStart = vestingConfig.start;
    _vestingCliff = (vestingConfig.vestingCliff * 1 days);

    initialised = true;
  }

  /**
   * @dev The Ether received will be logged with {PaymentReceived} events. Note that these events are not fully
   * reliable: it's possible for a contract to receive Ether without triggering this function. This only affects the
   * reliability of the events, and not the actual splitting of Ether.
   *
   * To learn more about this see the Solidity documentation for
   * https://solidity.readthedocs.io/en/latest/contracts.html#fallback-function[fallback
   * functions].
   */
  receive() external payable virtual {
    emit PaymentReceived(_msgSender(), msg.value);
  }

  /** ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   *
   * Getters: Shares
   *
   *  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   */

  /**
   * @dev Getter for the total shares held by payees.
   */
  function sharesTotal() public view returns (uint256) {
    return _totalShares;
  }

  /**
   * @dev Getter for the amount of shares held by the platform.
   */
  function sharesPlatform() public view returns (uint256) {
    return _platformShare;
  }

  /**
   * @dev Getter for the amount of shares held by the project that are vested.
   */
  function sharesProjectVested() public view returns (uint256) {
    return _projectVestedShare;
  }

  /**
   * @dev Getter for the amount of shares held by the project that are upfront.
   */
  function sharesProjectUpfront() public view returns (uint256) {
    return _projectUpfrontShare;
  }

  /** ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   *
   * Getters: Released Amounts, ETH
   *
   *  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   */

  /**
   * @dev Getter for the total amount of Ether already released.
   */
  function releasedETHTotal() public view returns (uint256) {
    return _totalETHReleased;
  }

  /**
   * @dev Getter for the amount of Ether already released to the platform.
   */
  function releasedETHPlatform() public view returns (uint256) {
    return _platformETHReleased;
  }

  /**
   * @dev Getter for the amount of ETH release for the project vested.
   */
  function releasedETHProjectVested() public view returns (uint256) {
    return _projectVestedETHReleased;
  }

  /**
   * @dev Getter for the amount of ETH release for the project upfront.
   */
  function releasedETHProjectUpfront() public view returns (uint256) {
    return _projectUpFrontETHReleased;
  }

  /** ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   *
   * Getters: Released Amounts, ERC20
   *
   *  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   */

  /**
   * @dev Getter for the total amount of `token` already released. `token` should be the address of an IERC20
   * contract.
   */
  function releasedERC20Total(IERC20 token) public view returns (uint256) {
    return _erc20TotalReleased[token];
  }

  /**
   * @dev Getter for the amount of `token` tokens already released to the platform. `token` should be the address of an
   * IERC20 contract.
   */
  function releasedERC20Platform(IERC20 token) public view returns (uint256) {
    return _platformERC20Released[token];
  }

  /**
   * @dev Getter for the amount of `token` tokens already released to the project vested. `token` should be the address of an
   * IERC20 contract.
   */
  function releasedERC20ProjectVested(
    IERC20 token
  ) public view returns (uint256) {
    return _projectVestedERC20Released[token];
  }

  /**
   * @dev Getter for the amount of `token` tokens already released to the project upfront. `token` should be the address of an
   * IERC20 contract.
   */
  function releasedERC20ProjectUpfront(
    IERC20 token
  ) public view returns (uint256) {
    return _projectUpfrontERC20Released[token];
  }

  /** ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   *
   * Getters: Addresses
   *
   *  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   */

  /**
   * @dev Getter for platform address
   */
  function platformAddress() public view returns (address) {
    return _platformAddress;
  }

  /**
   * @dev Getter for project addresses
   */
  function projectAddresses()
    public
    view
    returns (ProjectBeneficiary[] memory)
  {
    return _projectBeneficiaries;
  }

  /**
   * @dev Calculates the amount of ether that has already vested. Default implementation is a linear vesting curve.
   */
  function vestedAmountEth(
    uint256 balance,
    uint256 timestamp
  ) public view virtual returns (uint256) {
    return _vestingSchedule(balance, timestamp);
  }

  /**
   * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
   */
  function vestedAmountERC20(
    uint256 balance,
    uint256 timestamp
  ) public view virtual returns (uint256) {
    return _vestingSchedule(balance, timestamp);
  }

  /**
   * @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for
   * an asset given its total historical allocation.
   */
  function _vestingSchedule(
    uint256 totalAllocation,
    uint256 timestamp
  ) internal view virtual returns (uint256) {
    if (timestamp < (_vestingStart + _vestingCliff)) {
      return 0;
    } else if (timestamp > _vestingStart + _vestingPeriod) {
      return totalAllocation;
    } else {
      return (totalAllocation * (timestamp - _vestingStart)) / _vestingPeriod;
    }
  }

  /**
   * @dev Getter for the amount of the platform's releasable Ether.
   */
  function releasableETHPlatform() public view returns (uint256) {
    uint256 totalReceived = address(this).balance + releasedETHTotal();

    uint256 pendingPaymentByShares = _pendingPayment(
      _platformShare,
      totalReceived,
      releasedETHPlatform()
    );
    return (pendingPaymentByShares);
  }

  /**
   * @dev Getter for the amount of project's vested releasable Ether.
   */
  function releasableETHProjectVested() public view returns (uint256) {
    uint256 totalReceived = address(this).balance + releasedETHTotal();
    uint256 pendingPaymentByShares = _pendingPaymentVested(
      _projectVestedShare,
      totalReceived,
      releasedETHProjectVested()
    );
    return (pendingPaymentByShares);
  }

  /**
   * @dev Getter for the amount of the project's upfront releasable Ether.
   */
  function releasableETHProjectUpfront() public view returns (uint256) {
    uint256 totalReceived = address(this).balance + releasedETHTotal();
    uint256 pendingPaymentByShares = _pendingPayment(
      _projectUpfrontShare,
      totalReceived,
      releasedETHProjectUpfront()
    );
    return (pendingPaymentByShares);
  }

  /**
   * @dev Getter for the amount of platform's releasable `token` tokens. `token` should be the address of an
   * IERC20 contract.
   */
  function releasableERC20Platform(IERC20 token) public view returns (uint256) {
    uint256 totalReceived = token.balanceOf(address(this)) +
      releasedERC20Total(token);
    uint256 pendingPaymentByShares = _pendingPayment(
      _platformShare,
      totalReceived,
      releasedERC20Platform(token)
    );
    return (pendingPaymentByShares);
  }

  /**
   * @dev Getter for the amount of project's vested releasable `token` tokens. `token` should be the address of an
   * IERC20 contract.
   */
  function releasableERC20ProjectVested(
    IERC20 token
  ) public view returns (uint256) {
    uint256 totalReceived = token.balanceOf(address(this)) +
      releasedERC20Total(token);
    uint256 pendingPaymentByShares = _pendingPayment(
      _projectVestedShare,
      totalReceived,
      releasedERC20ProjectVested(token)
    );

    uint256 releasable = vestedAmountERC20(
      pendingPaymentByShares,
      block.timestamp
    );
    return (releasable);
  }

  /**
   * @dev Getter for the amount of project's releasable upfront `token` tokens. `token` should be the address of an
   * IERC20 contract.
   */
  function releasableERC20ProjectUpfront(
    IERC20 token
  ) public view returns (uint256) {
    uint256 totalReceived = token.balanceOf(address(this)) +
      releasedERC20Total(token);
    uint256 pendingPaymentByShares = _pendingPayment(
      _projectUpfrontShare,
      totalReceived,
      releasedERC20ProjectUpfront(token)
    );
    return (pendingPaymentByShares);
  }

  /**
   * @dev Triggers a transfer to the platform of the amount of Ether they are owed, according to their percentage of the
   * total shares and their previous withdrawals.
   */
  function releasePlatformETH() public virtual {
    require(_platformShare > 0, "No shares for this account");

    uint256 payment = releasableETHPlatform();

    require(payment != 0, "Nothing due");

    _platformETHReleased += payment;
    _totalETHReleased += payment;

    Address.sendValue(_platformAddress, payment);
    emit PaymentReleased(_platformAddress, payment);
  }

  /**
   * @dev Triggers a transfer to the project of the amount of Ether they are owed, according to their percentage of the
   * total shares and their previous withdrawals.
   */
  function releaseProjectETH(uint256 gasLimit_) public virtual {
    require(
      _projectUpfrontShare + _projectVestedShare > 0,
      "No shares for this account"
    );

    uint256 upfrontPayment = releasableETHProjectUpfront();
    uint256 vestedPayment = releasableETHProjectVested();

    require((upfrontPayment + vestedPayment) != 0, "Nothing due");

    _projectUpFrontETHReleased += upfrontPayment;
    _projectVestedETHReleased += vestedPayment;
    _totalETHReleased += (upfrontPayment + vestedPayment);

    // Distribute funds according to the project shares:
    for (uint256 i = 0; i < _projectBeneficiaries.length; ) {
      address payable payee = _projectBeneficiaries[i].payeeAddress;
      uint256 amount = ((upfrontPayment + vestedPayment) *
        _projectBeneficiaries[i].payeeShares) / _totalProjectShares;

      // If no gas limit was provided or provided gas limit greater than gas left, just use the remaining gas.
      uint256 gas = (gasLimit_ == 0 || gasLimit_ > gasleft())
        ? gasleft()
        : gasLimit_;

      (bool success, ) = payee.call{value: amount, gas: gas}("");
      // If the ETH transfer fails, wrap the ETH and try send it as WETH.
      if (!success) {
        weth.deposit{value: amount}();
        IERC20(address(weth)).safeTransfer(payee, amount);
      }

      emit PaymentReleased(payee, amount);

      unchecked {
        i++;
      }
    }
  }

  /**
   * @dev Triggers a transfer to the platform of the amount of `token` tokens they are owed, according to their
   * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
   * contract.
   */
  function releasePlatformERC20(IERC20 token) public virtual {
    require(_platformShare > 0, "No shares for this account");

    uint256 payment = releasableERC20Platform(token);

    require(payment != 0, "Nothing due");

    _platformERC20Released[token] += payment;
    _erc20TotalReleased[token] += payment;

    SafeERC20.safeTransfer(token, _platformAddress, payment);
    emit ERC20PaymentReleased(token, _platformAddress, payment);
  }

  /**
   * @dev Triggers a transfer to the project of the amount of `token` tokens they are owed, according to their
   * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
   * contract.
   */
  function releaseProjectERC20(IERC20 token) public virtual {
    require(
      _projectUpfrontShare + _projectVestedShare > 0,
      "No shares for this account"
    );

    uint256 upfrontPayment = releasableERC20ProjectUpfront(token);
    uint256 vestedPayment = releasableERC20ProjectVested(token);

    require((upfrontPayment + vestedPayment) != 0, "Nothing due");

    _projectUpfrontERC20Released[token] += upfrontPayment;
    _projectVestedERC20Released[token] += vestedPayment;
    _erc20TotalReleased[token] += (upfrontPayment + vestedPayment);

    // Distribute funds according to the project shares:
    for (uint256 i = 0; i < _projectBeneficiaries.length; ) {
      address payee = _projectBeneficiaries[i].payeeAddress;
      uint256 amount = ((upfrontPayment + vestedPayment) *
        _projectBeneficiaries[i].payeeShares) / _totalProjectShares;

      SafeERC20.safeTransfer(token, payee, amount);

      emit ERC20PaymentReleased(token, payee, amount);

      emit PaymentReleased(payee, amount);

      unchecked {
        i++;
      }
    }
  }

  /**
   * @dev internal logic for computing the pending payment of an `account` given the token historical balances and
   * already released amounts.
   */
  function _pendingPayment(
    uint256 shares_,
    uint256 totalReceived_,
    uint256 alreadyReleased_
  ) private view returns (uint256) {
    return ((totalReceived_ * shares_) / _totalShares) - alreadyReleased_;
  }

  /**
   * @dev internal logic for computing the pending payment of an `account` given the token historical balances and
   * already released amounts including vesting
   */
  function _pendingPaymentVested(
    uint256 shares_,
    uint256 totalReceived_,
    uint256 alreadyReleased_
  ) private view returns (uint256) {
    return (
      (vestedAmountEth(
        (totalReceived_ * shares_) / _totalShares,
        block.timestamp
      ) - alreadyReleased_)
    );
  }
}

