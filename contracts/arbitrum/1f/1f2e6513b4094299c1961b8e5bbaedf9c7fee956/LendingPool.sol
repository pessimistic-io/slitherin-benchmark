// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";

import "./ILendingPoolConfig.sol";
import "./IWAVAX.sol";


contract LendingPool is ERC20, ReentrancyGuard, Pausable, Ownable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Contract of pool's underlying asset
  IERC20 public immutable asset;
  // Pool config with interest rate model
  ILendingPoolConfig public immutable lendingPoolConfig;
  // Does pool accept native token?
  bool public immutable isNativeAsset;
  // Protocol treasury address
  address public treasury;
  // Asset decimals
  uint256 public immutable assetDecimals;
  // Amount borrowed from this pool
  uint256 public totalBorrows;
  // Total borrow shares in this pool
  uint256 public totalBorrowDebt;
  // The fee % applied to interest earned that goes to the protocol in 1e18
  uint256 public protocolFee;
  // Last updated timestamp of this pool
  uint256 public lastUpdatedAt;
  // Max capacity of vault in asset decimals / amt
  uint256 public maxCapacity;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== STRUCTS ========== */

  struct Borrower {
    // Boolean for whether borrower is approved to borrow from this pool
    bool approved;
    // Debt share of the borrower in this pool
    uint256 debt;
    // The last timestamp borrower borrowed from this pool
    uint256 lastUpdatedAt;
  }

  /* ========== MAPPINGS ========== */

  // Mapping of borrowers to borrowers struct
  mapping(address => Borrower) public borrowers;

  /* ========== EVENTS ========== */

  event Deposit(address indexed lender, uint256 depositShares, uint256 depositAmount);
  event Withdraw(address indexed withdrawer, uint256 withdrawShares, uint256 withdrawAmount);
  event Borrow(address indexed borrower, uint256 borrowDebt, uint256 borrowAmount);
  event Repay(address indexed borrower, uint256 repayDebt, uint256 repayAmount);
  event ProtocolFeeUpdated(address indexed caller, uint256 previousProtocolFee, uint256 newProtocolFee);
  event UpdateMaxCapacity(uint256 _maxCapacity);

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _name  Name for ibToken for this lending pool, e.g. Interest Bearing AVAX
    * @param _symbol  Symbol for ibToken for this lending pool, e.g. ibAVAX
    * @param _asset  Contract address for underlying ERC20 asset
    * @param _isNativeAsset  Boolean for whether this lending pool accepts the native asset (e.g. AVAX)
    * @param _protocolFee  Protocol fee in 1e18
    * @param _maxCapacity Max capacity of lending pool in asset decimals
    * @param _lendingPoolConfig  Contract for Lending Pool Configuration
    * @param _treasury  Contract address for protocol treasury
  */
  constructor(
    string memory _name,
    string memory _symbol,
    IERC20 _asset,
    bool _isNativeAsset,
    uint256 _protocolFee,
    uint256 _maxCapacity,
    ILendingPoolConfig _lendingPoolConfig,
    address _treasury
    ) ERC20(_name, _symbol) {
      require(address(_asset) != address(0), "invalid asset");
      require(address(_lendingPoolConfig) != address(0), "invalid lending pool config");
      require(_treasury != address(0), "invalid treasury");
      require(ERC20(address(_asset)).decimals() <= 18, "asset decimals must be <= 18");

      asset = _asset;
      isNativeAsset = _isNativeAsset;
      protocolFee = _protocolFee;
      lendingPoolConfig = _lendingPoolConfig;
      treasury = _treasury;
      maxCapacity = _maxCapacity;
      assetDecimals = ERC20(address(asset)).decimals();
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Returns the total value of the lending pool, i.e totalBorrows + interest + totalAvailableSupply
    * @return totalValue   Total value of lending pool in token decimals
  */
  function totalValue() public view returns (uint256) {
    uint256 interest = _pendingInterest(0);
    return totalBorrows + interest + totalAvailableSupply();
  }

  /**
    * Returns the available balance of asset in the pool
    * @return totalAvailableSupply   Balance of asset in the pool in token decimals
  */
  function totalAvailableSupply() public view returns (uint256) {
    return asset.balanceOf(address(this));
  }

  /**
    * Returns the the borrow utilization rate of the pool
    * @return utilizationRate   Ratio of borrows to total liquidity in 1e18
  */
  function utilizationRate() public view returns (uint256){
    uint256 totalValue_ = totalValue();

    return (totalValue_ == 0) ? 0 : totalBorrows * SAFE_MULTIPLIER / totalValue_;
  }

  /**
    * Returns the exchange rate for ibToken to asset
    * @return exchangeRate   Ratio of ibToken to underlying asset in token decimals
  */
  function exchangeRate() public view returns (uint256) {
    uint256 totalValue_ = totalValue();
    uint256 totalSupply_ = totalSupply();

    if (totalValue_ == 0 || totalSupply_ == 0) {
      return 1 * (10 ** assetDecimals);
    } else {
      return totalValue_ * SAFE_MULTIPLIER / totalSupply_;
    }
  }

  /**
    * Returns the current borrow APR
    * @return borrowAPR   Current borrow rate in 1e18
  */
  function borrowAPR() public view returns (uint256) {
    return lendingPoolConfig.interestRateAPR(totalBorrows, totalAvailableSupply());
  }

  /**
    * Returns the current lending APR; borrowAPR * utilization * (1 - protocolFee)
    * @return lendingAPR   Current lending rate in 1e18
  */
  function lendingAPR() public view returns (uint256) {
    uint256 borrowAPR_ = borrowAPR();
    uint256 utilizationRate_ = utilizationRate();

    if (borrowAPR_ == 0 || utilizationRate_ == 0) {
      return 0;
    } else {
      return borrowAPR_ * utilizationRate_
                         / SAFE_MULTIPLIER
                         * ((1 * SAFE_MULTIPLIER) - protocolFee)
                         / SAFE_MULTIPLIER;
    }
  }

  /**
    * Returns a borrower's maximum total repay amount taking into account ongoing interest
    * @param _address   Borrower's address
    * @return maxRepay   Borrower's total repay amount of assets in assets decimals
  */
  function maxRepay(address _address) public view returns (uint256) {
    if (totalBorrows == 0) {
      return 0;
    } else {
      uint256 interest = _pendingInterest(0);

      return borrowers[_address].debt * (totalBorrows + interest) / totalBorrowDebt;
    }
  }

  /* ========== MODIFIERS ========== */

  /**
    * Only allow approved addresses for borrowers
  */
  modifier onlyBorrower() {
    require(borrowers[msg.sender].approved, "Borrower not approved");
    _;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * Deposits asset into lending pool and mint ibToken to user
    * @param _assetAmount Amount of asset tokens to deposit in token decimals
    * @param _minSharesAmount Minimum amount of ibTokens tokens to receive on deposit
  */
  function deposit(uint256 _assetAmount, uint256 _minSharesAmount) external payable nonReentrant whenNotPaused {
    require(_assetAmount + totalValue() <= maxCapacity, "Exceeded max capacity");

    if (msg.value > 0) {
      require(isNativeAsset, "Only accepting native token");
      require(_assetAmount == msg.value, "Amount != msg.value");

      IWAVAX(address(asset)).deposit{ value: msg.value }();
    } else {
      require(!isNativeAsset, "Only accepting non-native token");
      require(_assetAmount > 0, "Deposited amount must be > 0");
      asset.safeTransferFrom(msg.sender, address(this), _assetAmount);
    }

    // Update pool with accrued interest and latest timestamp
    _updatePoolWithInterestsAndTimestamp(_assetAmount);

    uint256 sharesAmount = _mintShares(_assetAmount);

    require(sharesAmount >= _minSharesAmount, "Shares received less than minimum");

    emit Deposit(msg.sender, sharesAmount, _assetAmount);
  }

  /**
    * Withdraws asset from lending pool, burns ibToken from user
    * @param _ibTokenAmount Amount of ibTokens to burn in 1e18
    * @param _minWithdrawAmount Minimum amount of asset tokens to receive on withdrawal
  */
  function withdraw(uint256 _ibTokenAmount, uint256 _minWithdrawAmount) external nonReentrant whenNotPaused {
    require(_ibTokenAmount > 0, "Amount must be > 0");
    require(_ibTokenAmount <= balanceOf(msg.sender), "Withdraw amount exceeds balance");

    // Update pool with accrued interest and latest timestamp
    _updatePoolWithInterestsAndTimestamp(0);

    uint256 withdrawAmount = _burnShares(_ibTokenAmount);

    require(withdrawAmount >= _minWithdrawAmount, "Assets received less than minimum");

    if (isNativeAsset) {
      IWAVAX(address(asset)).withdraw(withdrawAmount);
      (bool success, ) = msg.sender.call{value: withdrawAmount}("");
      require(success, "Transfer failed.");
    } else {
      asset.safeTransfer(msg.sender, withdrawAmount);
    }

    emit Withdraw(msg.sender, _ibTokenAmount, withdrawAmount);
  }

  /**
    * Borrow asset from lending pool, adding debt
    * @param _borrowAmount Amount of tokens to borrow in token decimals
  */
  function borrow(uint256 _borrowAmount) external nonReentrant whenNotPaused onlyBorrower {
    require(_borrowAmount > 0, "Amount must be > 0");
    require(_borrowAmount <= totalAvailableSupply(), "Not enough lending liquidity to borrow");

    // Update pool with accrued interest and latest timestamp
    _updatePoolWithInterestsAndTimestamp(0);

    // Calculate debt amount
    uint256 debt = totalBorrows == 0 ? _borrowAmount : _borrowAmount * totalBorrowDebt / totalBorrows;

    // Update pool state
    totalBorrows = totalBorrows + _borrowAmount;
    totalBorrowDebt = totalBorrowDebt + debt;

    // Update borrower state
    Borrower storage borrower_ = borrowers[msg.sender];
    borrower_.debt = borrower_.debt + debt;
    borrower_.lastUpdatedAt = block.timestamp;

    // Transfer borrowed token from pool to manager
    asset.safeTransfer(msg.sender, _borrowAmount);

    emit Borrow(msg.sender, debt, _borrowAmount);
  }

  /**
    * Repay asset to lending pool, reducing debt
    * @param _repayAmount Amount of debt to repay in token decimals
  */
  function repay(uint256 _repayAmount) external nonReentrant whenNotPaused {
    require(_repayAmount > 0, "Amount must be > 0");

    // Update pool with accrued interest and latest timestamp
    _updatePoolWithInterestsAndTimestamp(0);

    uint256 maxRepay_ = maxRepay(msg.sender);

    require(maxRepay_ > 0, "Repay amount must be > 0");

    if (_repayAmount > maxRepay_) {
      _repayAmount = maxRepay_;
    }

    // Transfer repay tokens to the pool
    asset.safeTransferFrom(msg.sender, address(this), _repayAmount);

    uint256 borrowerTotalRepayAmount = maxRepay_;

    // Calculate debt to reduce based on repay amount
    uint256 debt = _repayAmount * borrowers[msg.sender].debt / borrowerTotalRepayAmount;

    // Update pool state
    totalBorrows = totalBorrows - _repayAmount;
    totalBorrowDebt = totalBorrowDebt - debt;

    // Update borrower state
    Borrower storage borrower_ = borrowers[msg.sender];
    borrower_.debt = borrower_.debt - debt;
    borrower_.lastUpdatedAt = block.timestamp;

    emit Repay(msg.sender, debt, _repayAmount);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * Calculate amount of ibTokens owed to depositor and mints them
    * @param _assetAmount  Amount of tokens to deposit in token decimals
    * @return shares  Amount of ibTokens minted in 1e18
  */
  function _mintShares(uint256 _assetAmount) internal returns (uint256) {
    // Calculate liquidity share amount
    uint256 shares = totalSupply() == 0 ?
      _assetAmount * _to18ConversionFactor() :
      _assetAmount * totalSupply() / (totalValue() - _assetAmount);

    // Mint ibToken to user equal to liquidity share amount
    _mint(msg.sender, shares);

    return shares;
  }

  /**
    * Calculate amount of asset owed to depositor based on ibTokens burned
    * @param _sharesAmount Amount of shares to burn in 1e18
    * @return withdrawAmount  Amount of assets withdrawn based on ibTokens burned in token decimals
  */
  function _burnShares(uint256 _sharesAmount) internal returns (uint256) {
    // Calculate amount of assets to withdraw based on shares to burn
    uint256 totalShares = totalSupply();
    uint256 withdrawAmount = totalShares == 0 ?
      0 :
      _sharesAmount * totalValue() / totalShares;

    // Burn user's ibTokens
    _burn(msg.sender, _sharesAmount);

    return withdrawAmount;
  }

  /**
    * Interest accrual function that calculates accumulated interest from lastUpdatedTimestamp and add to totalBorrows
    * @param _value Additonal amount of assets being deposited in token decimals
  */
  function _updatePoolWithInterestsAndTimestamp(uint256 _value) internal {
    uint256 interest = _pendingInterest(_value);
    uint256 toReserve = interest * protocolFee / SAFE_MULTIPLIER;
    asset.safeTransfer(treasury, toReserve);
    totalBorrows = totalBorrows + interest;
    lastUpdatedAt = block.timestamp;
  }

  /**
    * Returns the pending interest that will be accrued to the reserves in the next call
    * @param _value Newly deposited assets to be subtracted off total available liquidity in token decimals
    * @return interest  Amount of interest owned in token decimals
  */
  function _pendingInterest(uint256 _value) internal view returns (uint256) {
    if (totalBorrows == 0) return 0;

    uint256 totalAvailableSupply_ = totalAvailableSupply();
    uint256 timePassed = block.timestamp - lastUpdatedAt;
    uint256 floating = totalAvailableSupply_ == 0 ? 0 : totalAvailableSupply_ - _value;
    uint256 ratePerSec = lendingPoolConfig.interestRatePerSecond(totalBorrows, floating);

    // First division is due to ratePerSec being in 1e18
    // Second division is due to ratePerSec being in 1e18
    return ratePerSec * totalBorrows
      * timePassed
      / SAFE_MULTIPLIER;
  }

  /**
    * Conversion factor for tokens with less than 1e18 to return in 1e18
    * @return conversionFactor  Amount of decimals for conversion to 1e18
  */
  function _to18ConversionFactor() internal view returns (uint256) {
    unchecked {
      if (assetDecimals == 18) return 1;

      return 10**(18 - assetDecimals);
    }
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /**
    * Update protocol fee
    * @param _newProtocolFee  Fee percentage in 1e18
  */
  function updateProtocolFee(uint256 _newProtocolFee) external onlyOwner {
    // Update pool with accrued interest and latest timestamp
    _updatePoolWithInterestsAndTimestamp(0);

    emit ProtocolFeeUpdated(msg.sender, protocolFee, _newProtocolFee);

    protocolFee = _newProtocolFee;
  }

  /**
    * Approve address to borrow from this pool
    * @param _borrower  Borrower address
  */
  function approveBorrower(address _borrower) external onlyOwner {
    require(!borrowers[_borrower].approved, "Borrower already approved");

    borrowers[_borrower].approved = true;
  }

  /**
    * Revoke address to borrow from this pool
    * @param _borrower  Borrower address
  */
  function revokeBorrower(address _borrower) external onlyOwner {
    require(borrowers[_borrower].approved, "Borrower already revoked");

    borrowers[_borrower].approved = false;
  }

  /**
    * Emergency repay of assets to lending pool to clear bad debt
    * @param _repayAmount Amount of debt to repay in token decimals
  */
  function emergencyRepay(uint256 _repayAmount, address _defaulter) external nonReentrant whenPaused onlyOwner {
    require(_repayAmount > 0, "Amount must be > 0");

    uint256 maxRepay_ = maxRepay(_defaulter);

    require(maxRepay_ > 0, "Repay amount must be > 0");

    if (_repayAmount > maxRepay_) {
      _repayAmount = maxRepay_;
    }

    // Update pool with accrued interest and latest timestamp
    _updatePoolWithInterestsAndTimestamp(0);

    uint256 borrowerTotalRepayAmount = maxRepay_;

    // Calculate debt to reduce based on repay amount
    uint256 debt = _repayAmount * borrowers[_defaulter].debt / borrowerTotalRepayAmount;

    // Update pool state
    totalBorrows = totalBorrows - _repayAmount;
    totalBorrowDebt = totalBorrowDebt - debt;

    // Update borrower state
    borrowers[_defaulter].debt = borrowers[_defaulter].debt - debt;
    borrowers[_defaulter].lastUpdatedAt = block.timestamp;

    // Transfer repay tokens to the pool
    asset.safeTransferFrom(msg.sender, address(this), _repayAmount);

    emit Repay(msg.sender, debt, _repayAmount);
  }

  /**
    * Emergency pause of lending pool that pauses all deposits, borrows and normal withdrawals
  */
  function emergencyPause() external onlyOwner whenNotPaused {
    _pause();
  }

  /**
    * Emergency resume of lending pool that pauses all deposits, borrows and normal withdrawals
  */
  function emergencyResume() external onlyOwner whenPaused {
    _unpause();
  }

  /**
    * Update max capacity value
    * @param _maxCapacity Capacity value in token decimals (amount)
  */
  function updateMaxCapacity(uint256 _maxCapacity) external onlyOwner {
    maxCapacity = _maxCapacity;

    emit UpdateMaxCapacity(_maxCapacity);
  }

  /**
    * Update treasury address
    * @param _treasury Treasury address
  */
  function updateTreasury(address _treasury) external onlyOwner {
    require(_treasury != address(0), "Invalid address");
    treasury = _treasury;
  }

  /* ========== FALLBACK FUNCTIONS ========== */

  /**
    * Fallback function to receive native token sent to this contract,
    * needed for receiving native token to contract when unwrapped
  */
  receive() external payable {
    require(isNativeAsset, "Lending pool asset not native token");
  }
}

