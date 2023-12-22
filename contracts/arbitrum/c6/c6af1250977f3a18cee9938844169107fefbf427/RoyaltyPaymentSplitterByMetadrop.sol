// SPDX-License-Identifier: MIT
// Metadrop Contracts (v2.0.0)

/**
 *
 * @title RoyaltyPaymentSplitterByMetadrop.sol. OpenZepplin payment splitter with modifications to make cloneable
 *
 * @dev This contract allows to split Ether payments among a group of accounts. The sender does not need to be aware
 * that the Ether will be split in this way, since it is handled transparently by the contract.
 *
 * The split can be in equal parts or in any other arbitrary proportion. The way this is specified is by assigning each
 * account to a number of shares. Of all the Ether that this contract receives, each account will then be able to claim
 * an amount proportional to the percentage of total shares they were assigned. The distribution of shares is set at the
 * time of contract deployment and can't be updated thereafter.
 *
 * `PaymentSplitter` follows a _pull payment_ model. This means that payments are not automatically forwarded to the
 * accounts but kept in this contract, and the actual transfer is triggered as a separate step by calling the {release}
 * function.
 *
 * NOTE: This contract assumes that ERC20 tokens will behave similarly to native tokens (Ether). Rebasing tokens, and
 * tokens that apply fees during transfers, are likely to not be supported as expected. If in doubt, we encourage you
 * to run tests before sending real value to this contract.
 *
 * @author metadrop https://metadrop.com/
 *
 */

pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {Address} from "./Address.sol";
import {Context} from "./Context.sol";
import {IRoyaltyPaymentSplitterByMetadrop} from "./IRoyaltyPaymentSplitterByMetadrop.sol";
import {IErrors} from "./IErrors.sol";
import {Revert} from "./Revert.sol";

contract RoyaltyPaymentSplitterByMetadrop is
  IErrors,
  Revert,
  Context,
  IRoyaltyPaymentSplitterByMetadrop
{
  uint256 private constant ONE_HUNDRED_PERCENT_IN_BASIS_POINTS = 10000;

  uint256 private _totalShares;
  uint256 private _totalReleased;

  mapping(address => uint256) private _shares;
  mapping(address => uint256) private _released;
  address[] private _payees;

  mapping(IERC20 => uint256) private _erc20TotalReleased;
  mapping(IERC20 => mapping(address => uint256)) private _erc20Released;

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
  constructor() {
    initialised = true;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                         -->INITIALISE
   * @dev (function) initialiseRoyaltyPaymentSplitter  Initialise data on the royalty contract
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param royaltyModule_                        Configuration object for this instance of vesting
   * ---------------------------------------------------------------------------------------------------------------------
   * @param platformTreasury_                     The address for payments to the platform
   * ---------------------------------------------------------------------------------------------------------------------
   * @return royaltyFromSalesInBasisPoints_       The total royalty percentage (i.e. project + platform)
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function initialiseRoyaltyPaymentSplitter(
    RoyaltySplitterModuleConfig calldata royaltyModule_,
    address platformTreasury_
  ) external returns (uint96 royaltyFromSalesInBasisPoints_) {
    if (initialised) {
      _revert(AlreadyInitialised.selector);
    }

    initialised = true;

    // Decode the config:
    RoyaltyPaymentSplitterConfig memory royaltyConfig = abi.decode(
      royaltyModule_.configData,
      (RoyaltyPaymentSplitterConfig)
    );

    if (
      royaltyConfig.projectRoyaltyAddresses.length !=
      royaltyConfig.projectRoyaltySharesInBasisPoints.length
    ) {
      _revert(ListLengthMismatch.selector);
    }

    _addPayee(
      platformTreasury_,
      royaltyConfig.metadropShareOfRoyaltiesInBasisPoints
    );

    uint256 projectShareOfTotalShares = (ONE_HUNDRED_PERCENT_IN_BASIS_POINTS -
      royaltyConfig.metadropShareOfRoyaltiesInBasisPoints);

    uint256 totalProjectShares;
    for (uint256 i = 0; i < royaltyConfig.projectRoyaltyAddresses.length; ) {
      totalProjectShares += royaltyConfig.projectRoyaltySharesInBasisPoints[i];

      uint256 projectBeneficiaryShares = ((royaltyConfig
        .projectRoyaltySharesInBasisPoints[i] * projectShareOfTotalShares) /
        ONE_HUNDRED_PERCENT_IN_BASIS_POINTS);

      _addPayee(
        royaltyConfig.projectRoyaltyAddresses[i],
        projectBeneficiaryShares
      );

      unchecked {
        i++;
      }
    }

    if (totalProjectShares != ONE_HUNDRED_PERCENT_IN_BASIS_POINTS) {
      _revert(InvalidTotalShares.selector);
    }

    return (uint96(royaltyConfig.royaltyFromSalesInBasisPoints));
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

  /**
   * @dev Getter for the total shares held by payees.
   */
  function totalShares() public view returns (uint256) {
    return _totalShares;
  }

  /**
   * @dev Getter for the total amount of Ether already released.
   */
  function totalReleased() public view returns (uint256) {
    return _totalReleased;
  }

  /**
   * @dev Getter for the total amount of `token` already released. `token` should be the address of an IERC20
   * contract.
   */
  function totalReleased(IERC20 token) public view returns (uint256) {
    return _erc20TotalReleased[token];
  }

  /**
   * @dev Getter for the amount of shares held by an account.
   */
  function shares(address account) public view returns (uint256) {
    return _shares[account];
  }

  /**
   * @dev Getter for the amount of Ether already released to a payee.
   */
  function released(address account) public view returns (uint256) {
    return _released[account];
  }

  /**
   * @dev Getter for the amount of `token` tokens already released to a payee. `token` should be the address of an
   * IERC20 contract.
   */
  function released(
    IERC20 token,
    address account
  ) public view returns (uint256) {
    return _erc20Released[token][account];
  }

  /**
   * @dev Getter for the address of the payee number `index`.
   */
  function payee(uint256 index) public view returns (address) {
    return _payees[index];
  }

  /**
   * @dev Getter for the amount of payee's releasable Ether.
   */
  function releasable(address account) public view returns (uint256) {
    uint256 totalReceived = address(this).balance + totalReleased();
    return _pendingPayment(account, totalReceived, released(account));
  }

  /**
   * @dev Getter for the amount of payee's releasable `token` tokens. `token` should be the address of an
   * IERC20 contract.
   */
  function releasable(
    IERC20 token,
    address account
  ) public view returns (uint256) {
    uint256 totalReceived = token.balanceOf(address(this)) +
      totalReleased(token);
    return _pendingPayment(account, totalReceived, released(token, account));
  }

  /**
   * @dev Triggers a transfer to `account` of the amount of Ether they are owed, according to their percentage of the
   * total shares and their previous withdrawals.
   */
  function release(address payable account) public virtual {
    require(_shares[account] > 0, "PaymentSplitter: account has no shares");

    uint256 payment = releasable(account);

    require(payment != 0, "PaymentSplitter: account is not due payment");

    // _totalReleased is the sum of all values in _released.
    // If "_totalReleased += payment" does not overflow, then "_released[account] += payment" cannot overflow.
    _totalReleased += payment;
    unchecked {
      _released[account] += payment;
    }

    Address.sendValue(account, payment);
    emit PaymentReleased(account, payment);
  }

  /**
   * @dev Triggers a transfer to `account` of the amount of `token` tokens they are owed, according to their
   * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
   * contract.
   */
  function release(IERC20 token, address account) public virtual {
    require(_shares[account] > 0, "PaymentSplitter: account has no shares");

    uint256 payment = releasable(token, account);

    require(payment != 0, "PaymentSplitter: account is not due payment");

    // _erc20TotalReleased[token] is the sum of all values in _erc20Released[token].
    // If "_erc20TotalReleased[token] += payment" does not overflow, then "_erc20Released[token][account] += payment"
    // cannot overflow.
    _erc20TotalReleased[token] += payment;
    unchecked {
      _erc20Released[token][account] += payment;
    }

    SafeERC20.safeTransfer(token, account, payment);
    emit ERC20PaymentReleased(token, account, payment);
  }

  /**
   * @dev internal logic for computing the pending payment of an `account` given the token historical balances and
   * already released amounts.
   */
  function _pendingPayment(
    address account,
    uint256 totalReceived,
    uint256 alreadyReleased
  ) private view returns (uint256) {
    return (totalReceived * _shares[account]) / _totalShares - alreadyReleased;
  }

  /**
   * @dev Add a new payee to the contract.
   * @param account The address of the payee to add.
   * @param shares_ The number of shares owned by the payee.
   */
  function _addPayee(address account, uint256 shares_) private {
    require(
      account != address(0),
      "PaymentSplitter: account is the zero address"
    );
    require(shares_ > 0, "PaymentSplitter: shares are 0");
    require(
      _shares[account] == 0,
      "PaymentSplitter: account already has shares"
    );

    _payees.push(account);
    _shares[account] = shares_;
    _totalShares = _totalShares + shares_;
    emit PayeeAdded(account, shares_);
  }
}

