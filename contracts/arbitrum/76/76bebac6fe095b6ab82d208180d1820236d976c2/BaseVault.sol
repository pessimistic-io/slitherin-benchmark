// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IERC20} from "./ERC20_IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./security_ReentrancyGuard.sol";
import {Ownable} from "./Ownable.sol";
import {ERC20} from "./ERC20_ERC20.sol";
import {Initializable} from "./utils_Initializable.sol";
import {SafeMath} from "./SafeMath.sol";

import {Vault} from "./Vault.sol";
import {VaultLifecycle} from "./VaultLifecycle.sol";
import {ShareMath} from "./ShareMath.sol";
import {OwnableAdmins} from "./OwnableAdmins.sol";
import "./console.sol";

contract BaseVault is ReentrancyGuard, OwnableAdmins, Ownable, ERC20, Initializable {
  using SafeMath for uint;
  using SafeERC20 for IERC20;
  using ShareMath for Vault.DepositReceipt;

  bool public depositEnabled = true;

  /************************************************
   *  NON UPGRADEABLE STORAGE
   ***********************************************/

  /// @notice Stores the user's pending deposit for the round
  mapping(address => Vault.DepositReceipt) public depositReceipts;

  /// @notice On every round's close, the pricePerShare value of the Vault's
  //          token is stored
  /// This is used to determine the number of shares to be returned
  /// to a user with their DepositReceipt.depositAmount
  mapping(uint => uint) public roundPricePerShare;

  /// @notice Stores pending user withdrawals
  mapping(address => Vault.Withdrawal) public withdrawals;

  /// @notice Vault's parameters like cap, decimals
  Vault.VaultParams public vaultParams;

  /// @notice Vault's lifecycle state like round and locked amounts
  Vault.VaultState public vaultState;

  /// @notice Fee recipient for the license fees
  address public feeRecipient;

  /// @notice License fee charged on entire AUM in rollToNextOption. 
  uint public licenseFeeRate;

  // Gap is left to avoid storage collisions. Though RibbonVault is not upgradeable, we add this as a safety measure.
  uint[30] private ____gap;

  // *IMPORTANT* NO NEW STORAGE VARIABLES SHOULD BE ADDED HERE
  // This is to prevent storage collisions. All storage variables should be appended to RibbonThetaVaultStorage
  // or RibbonDeltaVaultStorage instead. Read this documentation to learn more:
  // https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts

  /************************************************
   *  IMMUTABLES & CONSTANTS
   ***********************************************/

  // Round per year scaled up FEE_MULTIPLIER
  uint private immutable roundPerYear;

  /************************************************
   *  EVENTS
   ***********************************************/

  //amount=amount for this deposit
  //walletDepositAmount=total pending deposit so far this round for wallet
  //vaultTotalPending=total pending deposit so far this round for entire vault
  event Deposit(address indexed account, uint amount,uint walletDepositAmount, uint vaultTotalPending, uint round);

  //shares=shares for this initial withdraw
  //walletWithdrawalShares=total withdraw initiated so far per wallet
  event InitiateWithdraw(address indexed account, uint shares, uint walletWithdrawalShares, uint round);

  event Redeem(address indexed account, uint share, uint round);

  event LicenseFeeRateSet(uint licenseFeeRate, uint newLicenseFeeRate);

  event CapSet(uint oldCap, uint newCap, address manager);

  event Withdraw(address indexed account, uint amount, uint shares);

  event CollectVaultFees(uint vaultFee, uint round, address indexed feeRecipient);

  /************************************************
   *  CONSTRUCTOR & INITIALIZATION
   ***********************************************/

  /**
   * @notice Initializes the contract with immutable variables
   */
  constructor(
    address _feeRecipient,
    uint _roundDuration,
    string memory _tokenName,
    string memory _tokenSymbol,
    Vault.VaultParams memory _vaultParams
  ) ERC20(_tokenName, _tokenSymbol) {
    feeRecipient = _feeRecipient;
    uint _roundPerYear = (uint(365 days) * Vault.FEE_MULTIPLIER) / _roundDuration;
    roundPerYear = _roundPerYear;
    vaultParams = _vaultParams;

    uint assetBalance = IERC20(vaultParams.asset).balanceOf(address(this));
    ShareMath.assertUint104(assetBalance);
    vaultState.lastLockedAmount = uint104(assetBalance);
    vaultState.round = 1;
  }

  /************************************************
   *  SETTERS
   ***********************************************/

  /**
   * @notice Sets the new fee recipient
   * @param newFeeRecipient is the address of the new fee recipient
   */
  function setFeeRecipient(address newFeeRecipient) external onlyAdmins {
    require(newFeeRecipient != address(0), "!newFeeRecipient");
    require(newFeeRecipient != feeRecipient, "Must be new feeRecipient");
    feeRecipient = newFeeRecipient;
  }

  /**
   * @notice Sets the license fee rate for the vault
   * @param newLicenseFeeRate is the license fee (6 decimals). ex: 2 * 10 ** 6 = 2%
   */
  function setLicenseFeeRate(uint newLicenseFeeRate) external onlyAdmins {
    require(newLicenseFeeRate < 100 * Vault.FEE_MULTIPLIER, "Invalid license fee rate");

    emit LicenseFeeRateSet(licenseFeeRate, newLicenseFeeRate);

    console.log("annualizedNewFeeRate=%s",newLicenseFeeRate);
    // We are dividing annualized license fee by number of rounds in a year
    licenseFeeRate = (newLicenseFeeRate * Vault.FEE_MULTIPLIER) / roundPerYear;
    console.log("newFeeRate=%s",licenseFeeRate);
  }

  /**
   * @notice Sets a new cap for deposits
   * @param newCap is the new cap for deposits
   */
  function setCap(uint newCap) external onlyAdmins {
    require(newCap > 0, "!newCap");

    emit CapSet(vaultParams.cap, newCap, msg.sender);

    ShareMath.assertUint104(newCap);
    vaultParams.cap = uint104(newCap);
  }

  function setDepositEnabled(bool _depositEnabled) external onlyAdmins {
    depositEnabled=_depositEnabled;
  }

  /************************************************
   *  DEPOSIT & WITHDRAWALS
   ***********************************************/

  /**
   * @notice Deposits the `asset` from msg.sender.
   * @param amount is the amount of `asset` to deposit
   */
  function deposit(uint amount) external nonReentrant {
    require(amount > 0, "!amount");

    _depositFor(amount, msg.sender);

    // An approve() by the msg.sender is required beforehand
    IERC20(vaultParams.asset).safeTransferFrom(msg.sender, address(this), amount);
  }

  /**
   * @notice Deposits the `asset` from msg.sender added to `creditor`'s deposit.
   * @notice Used for vault -> vault deposits on the user's behalf
   * @param amount is the amount of `asset` to deposit
   * @param creditor is the address that can claim/withdraw deposited amount
   */
  function depositFor(uint amount, address creditor) external nonReentrant {
    require(amount > 0, "!amount");
    require(creditor != address(0), "!creditor");

    _depositFor(amount, creditor);

    // An approve() by the msg.sender is required beforehand
    IERC20(vaultParams.asset).safeTransferFrom(msg.sender, address(this), amount);
  }

  /**
   * @notice Mints the vault shares to the creditor
   * @param amount is the amount of `asset` deposited
   * @param creditor is the address to receieve the deposit
   */
  function _depositFor(uint amount, address creditor) private {
    uint currentRound = vaultState.round;
    uint totalWithDepositedAmount = totalBalance() + amount;

    require(totalWithDepositedAmount <= vaultParams.cap, "Exceed cap");
    require(depositEnabled,"Deposit not enabled");

    Vault.DepositReceipt memory depositReceipt = depositReceipts[creditor];

    // process unprocessed pending deposit from the previous rounds
    uint unredeemedShares = depositReceipt.getSharesFromReceipt(
      currentRound,
      roundPricePerShare[depositReceipt.round],
      vaultParams.decimals
    );

    uint walletDepositAmount = amount;

    // If we have a pending deposit in the current round, we add on to the pending deposit
    if (currentRound == depositReceipt.round) {
      uint newAmount = uint(depositReceipt.amount) + amount;
      walletDepositAmount = newAmount;
    }

    ShareMath.assertUint104(walletDepositAmount);

    depositReceipts[creditor] = Vault.DepositReceipt({
      round: uint16(currentRound),
      amount: uint104(walletDepositAmount),
      unredeemedShares: uint128(unredeemedShares)
    });

    uint vaultTotalPending = uint(vaultState.totalPending) + amount;
    ShareMath.assertUint128(vaultTotalPending);


    emit Deposit(creditor, amount, walletDepositAmount, vaultTotalPending,currentRound);

    vaultState.totalPending = uint128(vaultTotalPending);
  }


  function initiateWithdraw(uint numShares) external nonReentrant {
    _initiateWithdraw(msg.sender,numShares,false);
  }

  function initiateWithdrawFor(address[] memory accounts) external onlyAdmins {
    for (uint i;i<accounts.length;i++) {
      _initiateWithdraw(accounts[i],0,true);
    }
  }

  /**
   * @notice Initiates a withdrawal that can be processed once the round completes
   * @param numShares is the number of shares to withdraw
   */
  function _initiateWithdraw(address account,uint numShares,bool isMax) private {
    if (numShares ==0 && !isMax) {
      console.log("zero shares");
      return;
    }

    // We do a max redeem before initiating a withdrawal
    // But we check if they must first have unredeemed shares
    if (depositReceipts[account].amount > 0 || depositReceipts[account].unredeemedShares > 0) {
      _redeem(account,0, true);
    }

    // This caches the `round` variable used in shareBalances
    uint currentRound = vaultState.round;
    Vault.Withdrawal storage withdrawal = withdrawals[account];

    bool withdrawalIsSameRound = withdrawal.round == currentRound;
    uint existingWithdrawalShares = uint(withdrawal.shares);
    console.log("initiateWithdraw for %s",account);
    //console.log("existingWithdrawalShares=%s/100, round=%s",existingWithdrawalShares/10**16,withdrawal.round);
    //console.log("withdrawalIsSameRound=%s",withdrawalIsSameRound);
    numShares = isMax ? shares(account) : numShares;

    //console.log('numShares = %s/100',numShares/10**16);
    if (numShares == 0) {
      return;
    } else if (numShares>shares(account)) {
      numShares = shares(account);
    }

    uint walletWithdrawalShares;
    if (withdrawalIsSameRound) {
        walletWithdrawalShares = existingWithdrawalShares + numShares;
    } else {
      if (existingWithdrawalShares > 0) {
        console.log("%s has existing withdraw",account);
        return;
      }
      walletWithdrawalShares = numShares;
      withdrawals[account].round = uint16(currentRound);
    }

    console.log("withdraw amount=%s/100",numShares/10**16);

    ShareMath.assertUint128(walletWithdrawalShares);
    withdrawals[account].shares = uint128(walletWithdrawalShares);

    uint newQueuedWithdrawShares = uint(vaultState.queuedWithdrawShares) + numShares;
    ShareMath.assertUint128(newQueuedWithdrawShares);
    vaultState.queuedWithdrawShares = uint128(newQueuedWithdrawShares);

    emit InitiateWithdraw(account, numShares, walletWithdrawalShares, currentRound);

    _transfer(account, address(this), numShares);
  }


  function completeWithdraw() external nonReentrant {
    _completeWithdraw(msg.sender);
  }

  function completeWithdrawFor(address[] memory accounts) external onlyAdmins {
    for (uint i;i<accounts.length;i++) {
      _completeWithdraw(accounts[i]);
    }
  }

  /**
   * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
   */
  function _completeWithdraw(address account) private {
    Vault.Withdrawal storage withdrawal = withdrawals[account];

    uint withdrawalShares = withdrawal.shares;
    uint withdrawalRound = withdrawal.round;

    // This checks if there is a withdrawal
    if (withdrawalShares == 0) {
      console.log("Not initiated for %s",account);
    } else if (withdrawalRound == vaultState.round) {
      console.log("%s needs to wait till next round",account);
    } else {
      // We leave the round number as non-zero to save on gas for subsequent writes
      withdrawals[account].shares = 0;
      vaultState.queuedWithdrawShares = uint128(uint(vaultState.queuedWithdrawShares) - withdrawalShares);

      uint withdrawAmount = ShareMath.sharesToAsset(withdrawalShares,roundPricePerShare[withdrawalRound],
        vaultParams.decimals);

      emit Withdraw(account, withdrawAmount, withdrawalShares);

      _burn(address(this), withdrawalShares);

      require(withdrawAmount > 0, "!withdrawAmount");

      _transferAsset(account, withdrawAmount);
    }
  }

  /**
   * @notice Redeems shares that are owed to the account
   * @param numShares is the number of shares to redeem
   */
  function redeem(uint numShares) external nonReentrant {
    require(numShares > 0, "!numShares");
    _redeem(msg.sender,numShares, false);
  }

  /**
   * @notice Redeems the entire unredeemedShares balance that is owed to the account
   */
  function maxRedeem() external nonReentrant {
    _redeem(msg.sender,0, true);
  }

  /**
   * @notice Redeems shares that are owed to the account
   * @param numShares is the number of shares to redeem, could be 0 when isMax=true
   * @param isMax is flag for when callers do a max redemption
   */
  function _redeem(address account,uint numShares, bool isMax) internal {
    Vault.DepositReceipt memory depositReceipt = depositReceipts[account];

    // This handles the null case when depositReceipt.round = 0
    // Because we start with round = 1 at `initialize`
    uint currentRound = vaultState.round;

    uint unredeemedShares = depositReceipt.getSharesFromReceipt(
      currentRound,roundPricePerShare[depositReceipt.round],vaultParams.decimals);


    numShares = isMax ? unredeemedShares : numShares;
    if (numShares == 0) {
      return;
    } else if (numShares>unredeemedShares) {
      numShares = unredeemedShares;
    }

    // If we have a depositReceipt on the same round, BUT we have some unredeemed shares
    // we debit from the unredeemedShares, but leave the amount field intact
    // If the round has past, with no new deposits, we just zero it out for new deposits.
    depositReceipts[account].amount = depositReceipt.round < currentRound ? 0 : depositReceipt.amount;

    ShareMath.assertUint128(numShares);
    depositReceipts[account].unredeemedShares = uint128(unredeemedShares - numShares);

    emit Redeem(account, numShares, depositReceipt.round);

    _transfer(address(this), account, numShares);
  }

  /************************************************
   *  VAULT OPERATIONS
   ***********************************************/

  /*
   * @notice Helper function that performs most administrative tasks
   * such as setting next option, minting new shares, getting vault fees, etc.
   * @param lastQueuedWithdrawAmount is old queued withdraw amount
   * @return lockedBalance is the new balance used to calculate next option purchase size or collateral size
   * @return queuedWithdrawAmount is the new queued withdraw amount for this round
   */
  function _rollToNextRound() internal returns (uint, uint,uint) {
    _collectVaultFees();
    (uint lockedBalance, uint queuedWithdrawAmount, uint newPricePerShare, uint mintShares) = VaultLifecycle.rollover(
      totalSupply(),
      vaultParams.asset,
      vaultParams.decimals,
      uint(vaultState.totalPending),
      vaultState.queuedWithdrawShares
    );

    // Finalize the pricePerShare at the end of the round
    uint currentRound = vaultState.round;
    roundPricePerShare[currentRound] = newPricePerShare;

    // update round info
    vaultState.totalPending = 0;
    vaultState.round = uint16(currentRound + 1);

    _mint(address(this), mintShares);

    return (lockedBalance, queuedWithdrawAmount,newPricePerShare);
  }

  function _collectVaultFees() internal returns (uint) {
    uint vaultFee = uint(vaultState.lastLockedAmount).mul(licenseFeeRate).div(100 * Vault.FEE_MULTIPLIER);

    if (vaultFee > 0) {
      _transferAsset(payable(feeRecipient), vaultFee);
      emit CollectVaultFees(vaultFee, vaultState.round, feeRecipient);
    }

    return vaultFee;
  }

  /**
   * @notice Helper function to make either an ETH transfer or ERC20 transfer
   * @param recipient is the receiving address
   * @param amount is the transfer amount
   */
  function _transferAsset(address recipient, uint amount) internal {
    address asset = vaultParams.asset;
    IERC20(asset).safeTransfer(recipient, amount);
  }

  /************************************************
   *  GETTERS
   ***********************************************/

  /**
   * @notice Returns the asset balance held on the vault for the account
   * @param account is the address to lookup balance for
   * @return the amount of `asset` custodied by the vault for the user
   */
  function accountVaultBalance(address account) external view returns (uint) {
    uint _decimals = vaultParams.decimals;
    uint assetPerShare = ShareMath.pricePerShare(totalSupply(), totalBalance(), vaultState.totalPending, _decimals);
    return ShareMath.sharesToAsset(shares(account), assetPerShare, _decimals);
  }

  /**
   * @notice Getter for returning the account's share balance including unredeemed shares
   * @param account is the account to lookup share balance for
   * @return the share balance
   */
  function shares(address account) public view returns (uint) {
    (uint heldByAccount, uint heldByVault) = shareBalances(account);
    return heldByAccount + heldByVault;
  }

  /**
   * @notice Getter for returning the account's share balance split between account and vault holdings
   * @param account is the account to lookup share balance for
   * @return heldByAccount is the shares held by account
   * @return heldByVault is the shares held on the vault (unredeemedShares)
   */
  function shareBalances(address account) public view returns (uint heldByAccount, uint heldByVault) {
    Vault.DepositReceipt memory depositReceipt = depositReceipts[account];

    if (depositReceipt.round == 0) {
      return (balanceOf(account), 0);
    }

    uint unredeemedShares = depositReceipt.getSharesFromReceipt(
      vaultState.round,
      roundPricePerShare[depositReceipt.round],
      vaultParams.decimals
    );

    return (balanceOf(account), unredeemedShares);
  }

  /**
   * @notice The price of a unit of share denominated in the `asset`
   */
  function pricePerShare() external view returns (uint) {
    return ShareMath.pricePerShare(totalSupply(), totalBalance(), vaultState.totalPending, vaultParams.decimals);
  }

  /**
   * @notice Returns the vault's total balance, including the amounts locked into a short position
   * @return total balance of the vault, including the amounts locked in third party protocols
   */
  function totalBalance() public view returns (uint) {
    return
      uint(vaultState.lockedAmount - vaultState.lockedAmountLeft) + IERC20(vaultParams.asset).balanceOf(address(this));
  }

  /**
   * @notice Returns the token decimals
   */
  function decimals() public view override returns (uint8) {
    return vaultParams.decimals;
  }
}

