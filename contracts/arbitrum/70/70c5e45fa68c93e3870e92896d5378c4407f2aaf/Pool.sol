// SPDX-License-Identifier: BUSL-1.1
// Last deployed from commit: 0586de75c558e4975c8569b88717b8c991307b9f;
pragma solidity 0.8.17;

import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20.sol";
import "./OwnableUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./TransferHelper.sol";
import "./Math.sol";
import "./IIndex.sol";
import "./IRatesCalculator.sol";
import "./IBorrowersRegistry.sol";
import "./IPoolRewarder.sol";
import "./VestingDistributor.sol";


/**
 * @title Pool
 * @dev Contract allowing user to deposit to and borrow from a dedicated user account
 * Depositors are rewarded with the interest rates collected from borrowers.
 * The interest rates calculation is delegated to an external calculator contract.
 */
contract Pool is OwnableUpgradeable, ReentrancyGuardUpgradeable, IERC20 {
    using TransferHelper for address payable;

    uint256 public totalSupplyCap;

    mapping(address => mapping(address => uint256)) private _allowed;
    mapping(address => uint256) internal _deposited;

    mapping(address => uint256) public borrowed;

    IRatesCalculator public ratesCalculator;
    IBorrowersRegistry public borrowersRegistry;
    IPoolRewarder public poolRewarder;

    IIndex public depositIndex;
    IIndex public borrowIndex;

    address payable public tokenAddress;

    VestingDistributor public vestingDistributor;

    uint8 internal _decimals;


    function initialize(IRatesCalculator ratesCalculator_, IBorrowersRegistry borrowersRegistry_, IIndex depositIndex_, IIndex borrowIndex_, address payable tokenAddress_, IPoolRewarder poolRewarder_, uint256 _totalSupplyCap) public initializer {
        require(AddressUpgradeable.isContract(address(ratesCalculator_))
            && AddressUpgradeable.isContract(address(borrowersRegistry_))
            && AddressUpgradeable.isContract(address(depositIndex_))
            && AddressUpgradeable.isContract(address(borrowIndex_))
            && (AddressUpgradeable.isContract(address(poolRewarder_)) || address(poolRewarder_) == address(0)), "Wrong init arguments");

        borrowersRegistry = borrowersRegistry_;
        ratesCalculator = ratesCalculator_;
        depositIndex = depositIndex_;
        borrowIndex = borrowIndex_;
        poolRewarder = poolRewarder_;
        tokenAddress = tokenAddress_;
        totalSupplyCap = _totalSupplyCap;

        _decimals = IERC20Metadata(tokenAddress_).decimals();

        __Ownable_init();
        __ReentrancyGuard_init();
        _updateRates();
    }

    /* ========== SETTERS ========== */

    /**
     * Sets new totalSupplyCap limiting how much in total can be deposited to the Pool.
     * Only the owner of the Contract can execute this function.
     * @dev _newTotalSupplyCap new deposit cap
    **/
    function setTotalSupplyCap(uint256 _newTotalSupplyCap) external onlyOwner {
        totalSupplyCap = _newTotalSupplyCap;
    }

    /**
     * Sets the new Pool Rewarder.
     * The IPoolRewarder that distributes additional token rewards to people having a stake in this pool proportionally to their stake and time of participance.
     * Only the owner of the Contract can execute this function.
     * @dev _poolRewarder the address of PoolRewarder
    **/
    function setPoolRewarder(IPoolRewarder _poolRewarder) external onlyOwner {
        if(!AddressUpgradeable.isContract(address(_poolRewarder)) && address(_poolRewarder) != address(0)) revert NotAContract(address(poolRewarder));
        poolRewarder = _poolRewarder;

        emit PoolRewarderChanged(address(_poolRewarder), block.timestamp);
    }

    /**
     * Sets the new rate calculator.
     * The calculator is an external contract that contains the logic for calculating deposit and borrowing rates.
     * Only the owner of the Contract can execute this function.
     * @dev ratesCalculator the address of rates calculator
     **/
    function setRatesCalculator(IRatesCalculator ratesCalculator_) external onlyOwner {
        // setting address(0) ratesCalculator_ freezes the pool
        if(!AddressUpgradeable.isContract(address(ratesCalculator_)) && address(ratesCalculator_) != address(0)) revert NotAContract(address(ratesCalculator_));
        ratesCalculator = ratesCalculator_;
        if (address(ratesCalculator_) != address(0)) {
            _updateRates();
        }

        emit RatesCalculatorChanged(address(ratesCalculator_), block.timestamp);
    }

    /**
     * Sets the new borrowers registry contract.
     * The borrowers registry decides if an account can borrow funds.
     * Only the owner of the Contract can execute this function.
     * @dev borrowersRegistry the address of borrowers registry
     **/
    function setBorrowersRegistry(IBorrowersRegistry borrowersRegistry_) external onlyOwner {
        if(!AddressUpgradeable.isContract(address(borrowersRegistry_))) revert NotAContract(address(borrowersRegistry_));

        borrowersRegistry = borrowersRegistry_;
        emit BorrowersRegistryChanged(address(borrowersRegistry_), block.timestamp);
    }

    /**
     * Sets the new Pool Rewarder.
     * The IPoolRewarder that distributes additional token rewards to people having a stake in this pool proportionally to their stake and time of participance.
     * Only the owner of the Contract can execute this function.
     * @dev _poolRewarder the address of PoolRewarder
    **/
    function setVestingDistributor(address _distributor) external onlyOwner {
        if(!AddressUpgradeable.isContract(_distributor) && _distributor != address(0)) revert NotAContract(_distributor);
        vestingDistributor = VestingDistributor(_distributor);

        emit VestingDistributorChanged(_distributor, block.timestamp);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function transfer(address recipient, uint256 amount) external override nonReentrant returns (bool) {
        if(recipient == address(0)) revert TransferToZeroAddress();

        if(recipient == address(this)) revert TransferToPoolAddress();

        address account = msg.sender;
        _accumulateDepositInterest(account);

        (uint256 lockedAmount, uint256 transferrableAmount) = _getAmounts(account);
        if(amount > transferrableAmount) revert TransferAmountExceedsBalance(amount, transferrableAmount);

        _updateWithdrawn(account, amount, lockedAmount);

        // (this is verified in "require" above)
        unchecked {
            _deposited[account] -= amount;
        }

        _accumulateDepositInterest(recipient);
        _deposited[recipient] += amount;

        // Handle rewards
        if(address(poolRewarder) != address(0) && amount != 0){
            uint256 unstaked = poolRewarder.withdrawFor(amount, account);
            if(unstaked > 0) {
                poolRewarder.stakeFor(unstaked, recipient);
            }
        }

        emit Transfer(account, recipient, amount);

        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowed[owner][spender];
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        if(spender == address(0)) revert SpenderZeroAddress();
        uint256 newAllowance = _allowed[msg.sender][spender] + addedValue;
        _allowed[msg.sender][spender] = newAllowance;

        emit Approval(msg.sender, spender, newAllowance);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        if(spender == address(0)) revert SpenderZeroAddress();
        uint256 currentAllowance = _allowed[msg.sender][spender];
        if(currentAllowance < subtractedValue) revert InsufficientAllowance(subtractedValue, currentAllowance);

        uint256 newAllowance = currentAllowance - subtractedValue;
        _allowed[msg.sender][spender] = newAllowance;

        emit Approval(msg.sender, spender, newAllowance);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        if(spender == address(0)) revert SpenderZeroAddress();
        _allowed[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override nonReentrant returns (bool) {
        if(_allowed[sender][msg.sender] < amount) revert InsufficientAllowance(amount, _allowed[sender][msg.sender]);

        if(recipient == address(0)) revert TransferToZeroAddress();

        if(recipient == address(this)) revert TransferToPoolAddress();

        _accumulateDepositInterest(sender);

        (uint256 lockedAmount, uint256 transferrableAmount) = _getAmounts(sender);
        if(amount > transferrableAmount) revert TransferAmountExceedsBalance(amount, transferrableAmount);

        _updateWithdrawn(sender, amount, lockedAmount);

        _deposited[sender] -= amount;
        _allowed[sender][msg.sender] -= amount;

        _accumulateDepositInterest(recipient);
        _deposited[recipient] += amount;

        // Handle rewards
        if(address(poolRewarder) != address(0) && amount != 0){
            uint256 unstaked = poolRewarder.withdrawFor(amount, sender);
            if(unstaked > 0) {
                poolRewarder.stakeFor(unstaked, recipient);
            }
        }

        emit Transfer(sender, recipient, amount);

        return true;
    }


    /**
     * Deposits the amount
     * It updates user deposited balance, total deposited and rates
     **/
    function deposit(uint256 _amount) public virtual {
        depositOnBehalf(_amount, msg.sender);
    }

    /**
     * Deposits the amount on behalf of `_of` user.
     * It updates `_of` user deposited balance, total deposited and rates
     **/
    function depositOnBehalf(uint256 _amount, address _of) public virtual nonReentrant {
        if(_amount == 0) revert ZeroDepositAmount();
        require(_of != address(0), "Address zero");
        require(_of != address(this), "Cannot deposit on behalf of pool");

        _amount = Math.min(_amount, IERC20(tokenAddress).balanceOf(msg.sender));

        _accumulateDepositInterest(_of);

        if(totalSupplyCap != 0){
            if(_deposited[address(this)] + _amount > totalSupplyCap) revert TotalSupplyCapBreached();
        }

        _transferToPool(msg.sender, _amount);

        _mint(_of, _amount);
        _deposited[address(this)] += _amount;
        _updateRates();

        if (address(poolRewarder) != address(0)) {
            poolRewarder.stakeFor(_amount, _of);
        }

        emit DepositOnBehalfOf(msg.sender, _of, _amount, block.timestamp);
    }

    function _transferToPool(address from, uint256 amount) internal virtual {
        tokenAddress.safeTransferFrom(from, address(this), amount);
    }

    function _transferFromPool(address to, uint256 amount) internal virtual {
        tokenAddress.safeTransfer(to, amount);
    }

    /**
     * Withdraws selected amount from the user deposits
     * @dev _amount the amount to be withdrawn
     **/
    function withdraw(uint256 _amount) external nonReentrant {
        _accumulateDepositInterest(msg.sender);
        _amount = Math.min(_amount, _deposited[msg.sender]);

        if(_amount > IERC20(tokenAddress).balanceOf(address(this))) revert InsufficientPoolFunds();

        if(_amount > _deposited[address(this)]) revert BurnAmountExceedsBalance();
        // verified in "require" above
        unchecked {
            _deposited[address(this)] -= _amount;
        }
        _burn(msg.sender, _amount);

        _updateRates();

        _transferFromPool(msg.sender, _amount);

        if (address(poolRewarder) != address(0)) {
            poolRewarder.withdrawFor(_amount, msg.sender);
        }

        emit Withdrawal(msg.sender, _amount, block.timestamp);
    }

    /**
     * Borrows the specified amount
     * It updates user borrowed balance, total borrowed amount and rates
     * @dev _amount the amount to be borrowed
     * @dev It is only meant to be used by a SmartLoanDiamondProxy
     **/
    function borrow(uint256 _amount) public virtual canBorrow nonReentrant {
        if (_amount > IERC20(tokenAddress).balanceOf(address(this))) revert InsufficientPoolFunds();

        _accumulateBorrowingInterest(msg.sender);

        borrowed[msg.sender] += _amount;
        borrowed[address(this)] += _amount;

        _transferFromPool(msg.sender, _amount);

        _updateRates();

        emit Borrowing(msg.sender, _amount, block.timestamp);
    }

    /**
     * Repays the amount
     * It updates user borrowed balance, total borrowed amount and rates
     * @dev It is only meant to be used by a SmartLoanDiamondProxy
     **/
    function repay(uint256 amount) external nonReentrant {
        _accumulateBorrowingInterest(msg.sender);

        if(amount > borrowed[msg.sender]) revert RepayingMoreThanWasBorrowed();
        _transferToPool(msg.sender, amount);

        borrowed[msg.sender] -= amount;
        borrowed[address(this)] -= amount;

        _updateRates();

        emit Repayment(msg.sender, amount, block.timestamp);
    }

    /* =========


    /**
     * Returns the current borrowed amount for the given user
     * The value includes the interest rates owned at the current moment
     * @dev _user the address of queried borrower
    **/
    function getBorrowed(address _user) public view returns (uint256) {
        return borrowIndex.getIndexedValue(borrowed[_user], _user);
    }

    function name() public virtual pure returns(string memory _name){
        _name = "";
    }

    function symbol() public virtual pure returns(string memory _symbol){
        _symbol = "";
    }

    function decimals() public virtual view returns(uint8){
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return balanceOf(address(this));
    }

    function totalBorrowed() public view returns (uint256) {
        return getBorrowed(address(this));
    }


    // Calls the IPoolRewarder.getRewardsFor() that sends pending rewards to msg.sender
    function getRewards() external {
        poolRewarder.getRewardsFor(msg.sender);
    }

    // Returns number of pending rewards for msg.sender
    function checkRewards() external view returns (uint256) {
        return poolRewarder.earned(msg.sender);
    }

    // Returns max. acceptable pool utilisation after borrow action
    function getMaxPoolUtilisationForBorrowing() virtual public view returns (uint256) {
        return 0.925e18;
    }

    /**
     * Returns the current deposited amount for the given user
     * The value includes the interest rates earned at the current moment
     * @dev _user the address of queried depositor
     **/
    function balanceOf(address user) public view override returns (uint256) {
        return depositIndex.getIndexedValue(_deposited[user], user);
    }

    /**
     * Returns the current interest rate for deposits
     **/
    function getDepositRate() public view returns (uint256) {
        return ratesCalculator.calculateDepositRate(totalBorrowed(), totalSupply());
    }

    /**
     * Returns the current interest rate for borrowings
     **/
    function getBorrowingRate() public view returns (uint256) {
        return ratesCalculator.calculateBorrowingRate(totalBorrowed(), totalSupply());
    }

    /**
     * Returns full pool status
     */
    function getFullPoolStatus() public view returns (uint256[5] memory) {
        return [
            totalSupply(),
            getDepositRate(),
            getBorrowingRate(),
            totalBorrowed(),
            getMaxPoolUtilisationForBorrowing()
        ];
    }

    /**
     * Recovers the surplus funds resultant from difference between deposit and borrowing rates
     **/
    function recoverSurplus(uint256 amount, address account) public onlyOwner nonReentrant {
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        uint256 surplus = balance + totalBorrowed() - totalSupply();

        if(amount > balance) revert InsufficientPoolFunds();
        if(surplus < amount) revert InsufficientSurplus();

        _transferFromPool(account, amount);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _mint(address to, uint256 amount) internal {
        if(to == address(0)) revert MintToAddressZero();

        _deposited[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    function _burn(address account, uint256 amount) internal {
        if(amount > _deposited[account]) revert BurnAmountExceedsBalance();
        (uint256 lockedAmount, uint256 transferrableAmount) = _getAmounts(account);
        if(amount > transferrableAmount) revert BurnAmountExceedsAvailableForUser();

        _updateWithdrawn(account, amount, lockedAmount);

        // verified in "require" above
        unchecked {
            _deposited[account] -= amount;
        }

        emit Transfer(account, address(0), amount);
    }

    function _getAmounts(address account) internal view returns (uint256 lockedAmount, uint256 transferrableAmount) {
        if (address(vestingDistributor) != address(0)) {
            lockedAmount = vestingDistributor.locked(account);
            if (lockedAmount > 0) {
                transferrableAmount = _deposited[account] - (lockedAmount - vestingDistributor.availableToWithdraw(account));
            } else {
                transferrableAmount = _deposited[account];
            }
        } else {
            transferrableAmount = _deposited[account];
        }
    }

    function _updateWithdrawn(address account, uint256 amount, uint256 lockedAmount) internal {
        uint256 availableUnvested = _deposited[account] - lockedAmount;
        if (amount > availableUnvested && address(vestingDistributor) != address(0)) {
            vestingDistributor.updateWithdrawn(account, amount - availableUnvested);
        }
    }

    function _updateRates() internal {
        uint256 _totalBorrowed = totalBorrowed();
        uint256 _totalSupply = totalSupply();
        if(address(ratesCalculator) == address(0)) revert PoolFrozen();
        depositIndex.setRate(ratesCalculator.calculateDepositRate(_totalBorrowed, _totalSupply));
        borrowIndex.setRate(ratesCalculator.calculateBorrowingRate(_totalBorrowed, _totalSupply));
    }

    function _accumulateDepositInterest(address user) internal {
        uint256 interest = balanceOf(user) - _deposited[user];

        _mint(user, interest);
        _deposited[address(this)] = balanceOf(address(this));

        emit InterestCollected(user, interest, block.timestamp);

        depositIndex.updateUser(user);
        depositIndex.updateUser(address(this));
    }

    function _accumulateBorrowingInterest(address user) internal {
        borrowed[user] = getBorrowed(user);
        borrowed[address(this)] = getBorrowed(address(this));

        borrowIndex.updateUser(user);
        borrowIndex.updateUser(address(this));
    }

    /* ========== OVERRIDDEN FUNCTIONS ========== */

    function renounceOwnership() public virtual override {}

    /* ========== MODIFIERS ========== */

    modifier canBorrow() {
        if(address(borrowersRegistry) == address(0)) revert BorrowersRegistryNotConfigured();
        if(!borrowersRegistry.canBorrow(msg.sender)) revert NotAuthorizedToBorrow();
        if(totalSupply() == 0) revert InsufficientPoolFunds();
        _;
        if((totalBorrowed() * 1e18) / totalSupply() > getMaxPoolUtilisationForBorrowing()) revert MaxPoolUtilisationBreached();
    }

    /* ========== EVENTS ========== */

    /**
     * @dev emitted after the user deposits funds
     * @param user the address performing the deposit
     * @param value the amount deposited
     * @param timestamp of the deposit
     **/
    event Deposit(address indexed user, uint256 value, uint256 timestamp);

    /**
     * @dev emitted after the user deposits funds on behalf of other user
     * @param user the address performing the deposit
     * @param _of the address on behalf of which the deposit is being performed
     * @param value the amount deposited
     * @param timestamp of the deposit
     **/
    event DepositOnBehalfOf(address indexed user, address indexed _of, uint256 value, uint256 timestamp);

    /**
     * @dev emitted after the user withdraws funds
     * @param user the address performing the withdrawal
     * @param value the amount withdrawn
     * @param timestamp of the withdrawal
     **/
    event Withdrawal(address indexed user, uint256 value, uint256 timestamp);

    /**
     * @dev emitted after the user borrows funds
     * @param user the address that borrows
     * @param value the amount borrowed
     * @param timestamp time of the borrowing
     **/
    event Borrowing(address indexed user, uint256 value, uint256 timestamp);

    /**
     * @dev emitted after the user repays debt
     * @param user the address that repays debt
     * @param value the amount repaid
     * @param timestamp of the repayment
     **/
    event Repayment(address indexed user, uint256 value, uint256 timestamp);

    /**
     * @dev emitted after accumulating deposit interest
     * @param user the address that the deposit interest is accumulated for
     * @param value the amount that interest is calculated from
     * @param timestamp of the interest accumulation
     **/
    event InterestCollected(address indexed user, uint256 value, uint256 timestamp);

    /**
    * @dev emitted after changing borrowers registry
    * @param registry an address of the newly set borrowers registry
    * @param timestamp of the borrowers registry change
    **/
    event BorrowersRegistryChanged(address indexed registry, uint256 timestamp);

    /**
    * @dev emitted after changing rates calculator
    * @param calculator an address of the newly set rates calculator
    * @param timestamp of the borrowers registry change
    **/
    event RatesCalculatorChanged(address indexed calculator, uint256 timestamp);

    /**
    * @dev emitted after changing pool rewarder
    * @param poolRewarder an address of the newly set pool rewarder
    * @param timestamp of the pool rewarder change
    **/
    event PoolRewarderChanged(address indexed poolRewarder, uint256 timestamp);

    /**
    * @dev emitted after changing vesting distributor
    * @param distributor an address of the newly set distributor
    * @param timestamp of the distributor change
    **/
    event VestingDistributorChanged(address indexed distributor, uint256 timestamp);

    /* ========== ERRORS ========== */

    // Only authorized accounts may borrow
    error NotAuthorizedToBorrow();

    // Borrowers registry is not configured
    error BorrowersRegistryNotConfigured();

    // Pool is frozen
    error PoolFrozen();

    // Not enough funds in the pool.
    error InsufficientPoolFunds();

    // Insufficient pool surplus to cover the requested recover amount
    error InsufficientSurplus();

    // Address (`target`) must be a contract
    // @param target target address that must be a contract
    error NotAContract(address target);

    //  ERC20: Spender cannot be a zero address
    error SpenderZeroAddress();

    //  ERC20: cannot transfer to the zero address
    error TransferToZeroAddress();

    //  ERC20: cannot transfer to the pool address
    error TransferToPoolAddress();

    //  ERC20: transfer amount (`amount`) exceeds balance (`balance`)
    /// @param amount transfer amount
    /// @param balance available balance
    error TransferAmountExceedsBalance(uint256 amount, uint256 balance);

    //  ERC20: requested transfer amount (`requested`) exceeds current allowance (`allowance`)
    /// @param requested requested transfer amount
    /// @param allowance current allowance
    error InsufficientAllowance(uint256 requested, uint256 allowance);

    //  This deposit operation would result in a breach of the totalSupplyCap
    error TotalSupplyCapBreached();

    // The deposit amount must be > 0
    error ZeroDepositAmount();

    // ERC20: cannot mint to the zero address
    error MintToAddressZero();

    // ERC20: burn amount exceeds current pool indexed balance
    error BurnAmountExceedsBalance();

    // ERC20: burn amount exceeds current amount available (including vesting)
    error BurnAmountExceedsAvailableForUser();

    // Trying to repay more than was borrowed
    error RepayingMoreThanWasBorrowed();

    // getMaxPoolUtilisationForBorrowing was breached
    error MaxPoolUtilisationBreached();
}
