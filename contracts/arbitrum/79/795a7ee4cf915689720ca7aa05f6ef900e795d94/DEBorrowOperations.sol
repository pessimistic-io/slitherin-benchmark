// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./UnboundBase.sol";

import "./IBorrowoperations.sol";
import "./IDEAccountManager.sol";

import "./DESharePriceProvider.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./Initializable.sol";

// BorrowOperations - add collatreral, remove collaral, mint UND, repay UND, 
contract DEBorrowOperations is UnboundBase, Initializable, IBorrowoperations {

    using SafeERC20 for IERC20;

    IDEAccountManager public accountManager;

    address public override governanceFeeAddress;

    struct ContractsCache {
        IDEAccountManager accountManager;
        IMainPool mainPool;
        IERC20 depositToken;
        IUNDToken undToken;
        IUnboundFeesFactory unboundFeesFactory;
        address governanceFeeAddress;
    }

    struct LocalVariables_openAccount {
        uint price;
        uint UNDFee;
        uint netDebt;
        uint ICR;
        uint NICR;
        uint arrayIndex;
    }

    /* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

     struct LocalVariables_adjustAccount {
        uint price;
        uint collChange;
        uint netDebtChange;
        bool isCollIncrease;
        uint debt;
        uint coll;
        uint oldICR;
        uint newICR;
        uint UNDFee;
        uint newDebt;
        uint newColl;
    }

    function initialize (
        address _accountManager
    ) 
        public 
        initializer
    {
        accountManager = IDEAccountManager(_accountManager);
        undToken = accountManager.undToken();
        sortedAccounts = accountManager.sortedAccounts();
        depositToken = accountManager.depositToken();
        mainPool = accountManager.mainPool();
        unboundFeesFactory = accountManager.unboundFeesFactory();
        collSurplusPool = accountManager.collSurplusPool();
        governanceFeeAddress = accountManager.governanceFeeAddress();
        MCR = accountManager.MCR();
    }

    function openAccount(uint256 _maxFeePercentage, uint256 _collAmount, uint256 _UNDAmount, address _upperHint, address _lowerHint) external override {
        ContractsCache memory contractsCache = ContractsCache(accountManager, mainPool, depositToken, undToken, unboundFeesFactory, governanceFeeAddress);
        LocalVariables_openAccount memory vars;

        // check if fee percentage is valid
        _requireValidMaxFeePercentage(_maxFeePercentage);

        // check if account is already created or not
        _requireAccountisNotActive(contractsCache.accountManager, msg.sender);

        // get price of pool token from oracle
        vars.price = uint256 (DESharePriceProvider.latestAnswer(contractsCache.accountManager));

        vars.UNDFee;
        vars.netDebt = _UNDAmount;

        vars.UNDFee = _triggerBorrowingFee(contractsCache.unboundFeesFactory, contractsCache.undToken, _UNDAmount, _maxFeePercentage, contractsCache.governanceFeeAddress);
        vars.netDebt = vars.netDebt + vars.UNDFee;

        _requireAtLeastMinNetDebt(vars.netDebt);
        _requireMaxUNDMintLimitNotReached(contractsCache.mainPool, vars.netDebt);

        // ICR is based on the net debt, i.e. the requested UND amount + UND borrowing fee.
        vars.ICR = UnboundMath._computeCR(_collAmount, vars.netDebt, vars.price);
        vars.NICR = UnboundMath._computeNominalCR(_collAmount, vars.netDebt);

        _requireICRisAboveMCR(vars.ICR);

        // Set the account struct's properties
        contractsCache.accountManager.setAccountStatus(msg.sender, 1);
        contractsCache.accountManager.increaseAccountColl(msg.sender, _collAmount);
        contractsCache.accountManager.increaseAccountDebt(msg.sender, vars.netDebt);

        sortedAccounts.insert(msg.sender, vars.NICR, _upperHint, _lowerHint);
        vars.arrayIndex = contractsCache.accountManager.addAccountOwnerToArray(msg.sender);
        emit AccountCreated(msg.sender, vars.arrayIndex);

        // Move the LP collateral to the this contract, and mint the UNDAmount to the borrower
        _mainPoolAddColl(contractsCache.depositToken, contractsCache.mainPool, _collAmount);

        //stake collaterar to farming contract for rewards
        contractsCache.mainPool.stake(msg.sender, _collAmount);

        _withdrawUND(contractsCache.mainPool, contractsCache.undToken, msg.sender, _UNDAmount, vars.netDebt);

        emit AccountUpdated(msg.sender, vars.netDebt, _collAmount, BorrowerOperation.openAccount);
        emit UNDBorrowingFeePaid(msg.sender, vars.UNDFee);

    }

    // Send LP token as collateral to a account
    function addColl(uint256 _collDeposit, address _upperHint, address _lowerHint) external override {
        _adjustAccount(msg.sender, _collDeposit, 0, 0, false, _upperHint, _lowerHint, 0);
    }

    // Withdraw LP token collateral from a account
    function withdrawColl(uint _collWithdrawal, address _upperHint, address _lowerHint) external override {
        _adjustAccount(msg.sender, 0, _collWithdrawal, 0, false, _upperHint, _lowerHint, 0);
    }

    // Withdraw UND tokens from a account: mint new UND tokens to the owner, and increase the account's debt accordingly
    function withdrawUND(uint _maxFeePercentage, uint _UNDAmount, address _upperHint, address _lowerHint) external override {
        _adjustAccount(msg.sender, 0, 0, _UNDAmount, true, _upperHint, _lowerHint, _maxFeePercentage);
    }

    // Repay UND tokens to a Account: Burn the repaid UND tokens, and reduce the account's debt accordingly
    function repayUND(uint _UNDAmount, address _upperHint, address _lowerHint) external override {
        _adjustAccount(msg.sender, 0, 0, _UNDAmount, false, _upperHint, _lowerHint, 0);
    }

    function adjustAccount(uint _maxFeePercentage, uint256 _collDeposit, uint _collWithdrawal, uint _UNDChange, bool _isDebtIncrease, address _upperHint, address _lowerHint) external override {
        _adjustAccount(msg.sender, _collDeposit, _collWithdrawal, _UNDChange, _isDebtIncrease, _upperHint, _lowerHint, _maxFeePercentage);
    }

    /*
    * _adjustAccount(): Alongside a debt change, this function can perform either a collateral top-up or a collateral withdrawal. 
    *
    * It therefore expects either a positive msg.value, or a positive _collWithdrawal argument.
    *
    * If both are positive, it will revert.
    */
    function _adjustAccount(address _borrower, uint256 _collDeposit, uint _collWithdrawal, uint _UNDChange, bool _isDebtIncrease, address _upperHint, address _lowerHint, uint _maxFeePercentage) internal {
        ContractsCache memory contractsCache = ContractsCache(accountManager, mainPool, depositToken, undToken, unboundFeesFactory, governanceFeeAddress);
        LocalVariables_adjustAccount memory vars;

        // get price of pool token from oracle
        vars.price = uint256 (DESharePriceProvider.latestAnswer(contractsCache.accountManager));

        if (_isDebtIncrease) {
            _requireValidMaxFeePercentage(_maxFeePercentage);
            _requireNonZeroDebtChange(_UNDChange);
        }
        _requireSingularCollChange(_collDeposit, _collWithdrawal);
        _requireNonZeroAdjustment(_collDeposit, _collWithdrawal, _UNDChange);
        _requireAccountisActive(contractsCache.accountManager, _borrower);

        // Get the collChange based on whether or not Coll was sent in the transaction
        (vars.collChange, vars.isCollIncrease) = _getCollChange(_collDeposit, _collWithdrawal);

        vars.netDebtChange = _UNDChange;

        // If the adjustment incorporates a debt increase, then trigger a borrowing fee
        if (_isDebtIncrease) { 
            vars.UNDFee = _triggerBorrowingFee(contractsCache.unboundFeesFactory, contractsCache.undToken, _UNDChange, _maxFeePercentage, contractsCache.governanceFeeAddress);
            vars.netDebtChange = vars.netDebtChange + vars.UNDFee; // The raw debt change includes the fee
            _requireMaxUNDMintLimitNotReached(contractsCache.mainPool, vars.netDebtChange);
        }

        vars.debt = contractsCache.accountManager.getAccountDebt(_borrower);
        vars.coll = contractsCache.accountManager.getAccountColl(_borrower);
        
        _requireValidCollWithdrawal(_collWithdrawal, vars.coll);

        // When the adjustment is a debt repayment, check it's a valid amount and that the caller has enough UND
        if (!_isDebtIncrease && _UNDChange > 0) {
            _requireValidUNDRepayment(vars.debt, vars.netDebtChange);
            _requireAtLeastMinNetDebt(vars.debt - vars.netDebtChange);
            _requireSufficientUNDBalance(contractsCache.undToken, _borrower, vars.netDebtChange);
        }

        // Get the account's old ICR before the adjustment, and what its new ICR will be after the adjustment
        vars.oldICR = UnboundMath._computeCR(vars.coll, vars.debt, vars.price);
        vars.newICR = _getNewICRFromAccountChange(vars.coll, vars.debt, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease, vars.price);

        // Check the adjustment satisfies all conditions
        _requireICRisAboveMCR(vars.newICR);
        // _requireValidAdjustment(_isDebtIncrease, vars);

        (vars.newColl, vars.newDebt) = _updateAccountFromAdjustment(contractsCache.accountManager, _borrower, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease);
        
        // Re-insert account in to the sorted list
        uint newNICR = UnboundMath._computeNominalCR(vars.newColl, vars.newDebt);
        sortedAccounts.reInsert(_borrower, newNICR, _upperHint, _lowerHint);

        emit AccountUpdated(_borrower, vars.newDebt, vars.newColl, BorrowerOperation.adjustAccount);
        emit UNDBorrowingFeePaid(msg.sender,  vars.UNDFee);

        // Use the unmodified _UNDChange here, as we don't send the fee to the user
        _moveTokensAndCollateralfromAdjustment(
            contractsCache.depositToken,
            contractsCache.mainPool,
            contractsCache.undToken,
            msg.sender,
            vars.collChange,
            vars.isCollIncrease,
            _UNDChange,
            _isDebtIncrease,
            vars.netDebtChange
        );
    }

    function closeAccount() external override {
        ContractsCache memory contractsCache = ContractsCache(accountManager, mainPool, depositToken, undToken, unboundFeesFactory, governanceFeeAddress);

        _requireAccountisActive(contractsCache.accountManager, msg.sender);

        // accountManagerCached.applyPendingRewards(msg.sender);

        uint coll = contractsCache.accountManager.getAccountColl(msg.sender);
        uint debt = contractsCache.accountManager.getAccountDebt(msg.sender);

        _requireSufficientUNDBalance(contractsCache.undToken, msg.sender, debt);

        // accountManagerCached.removeStake(msg.sender);
        contractsCache.accountManager.closeAccount(msg.sender);

        emit AccountUpdated(msg.sender, 0, 0, BorrowerOperation.closeAccount);

        // Burn the repaid UND from the user's balance
        _repayUND(contractsCache.mainPool, contractsCache.undToken, msg.sender, debt);

        // unstake collateral from farming contract
        contractsCache.mainPool.unstake(msg.sender, coll);

        // Send the collateral back to the user
        contractsCache.mainPool.sendCollateral(contractsCache.depositToken, msg.sender, coll);
    }

    /**
     * Claim remaining collateral from a redemption
     */
    function claimCollateral() external override {
        // send ETH from CollSurplus Pool to owner
        collSurplusPool.claimColl(depositToken, msg.sender);
    }

    /**
     * Return Unbound Fees Factory contract address (to validate minter in UND contract)
     */
    function factory() external override view returns(address){
        return address(unboundFeesFactory);
    }

    /**
     * Return Collateral Price in USD, for UI. Use static call to fetch price
     */
    function getCollPrice() external returns(uint256){
        return uint256 (DESharePriceProvider.latestAnswer(accountManager));
    }

    // --- Helper functions ---

    function _triggerBorrowingFee(IUnboundFeesFactory _unboundFeesFactory, IUNDToken _undToken, uint _UNDAmount, uint _maxFeePercentage, address safu) internal returns (uint) {
        _unboundFeesFactory.decayBaseRateFromBorrowing(); // decay the baseRate state variable
        uint UNDFee = _unboundFeesFactory.getBorrowingFee(_UNDAmount);

        _requireUserAcceptsFee(UNDFee, _UNDAmount, _maxFeePercentage);
        
        // Send fees to governance fee address address
        _undToken.mint(safu, UNDFee);

        return UNDFee;
    }

    function _getCollChange(
        uint _collReceived,
        uint _requestedCollWithdrawal
    )
        internal
        pure
        returns(uint collChange, bool isCollIncrease)
    {
        if (_collReceived != 0) {
            collChange = _collReceived;
            isCollIncrease = true;
        } else {
            collChange = _requestedCollWithdrawal;
        }
    }

    // Update account's coll and debt based on whether they increase or decrease
    function _updateAccountFromAdjustment
    (
        IDEAccountManager _accountManager,
        address _borrower,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        internal
        returns (uint, uint)
    {
        uint newColl = (_isCollIncrease) ? _accountManager.increaseAccountColl(_borrower, _collChange)
                                        : _accountManager.decreaseAccountColl(_borrower, _collChange);
        uint newDebt = (_isDebtIncrease) ? _accountManager.increaseAccountDebt(_borrower, _debtChange)
                                        : _accountManager.decreaseAccountDebt(_borrower, _debtChange);

        return (newColl, newDebt);
    }

    function _moveTokensAndCollateralfromAdjustment
    (
        IERC20 _depositToken,
        IMainPool _mainPool,
        IUNDToken _undToken,
        address _borrower,
        uint _collChange,
        bool _isCollIncrease,
        uint _UNDChange,
        bool _isDebtIncrease,
        uint _netDebtChange
    )
        internal
    {
        if (_isDebtIncrease) {
            _withdrawUND(_mainPool, _undToken, _borrower, _UNDChange, _netDebtChange);
        } else {
            _repayUND(_mainPool, _undToken, _borrower, _UNDChange);
        }

        if (_isCollIncrease) {
            _mainPoolAddColl(_depositToken, _mainPool, _collChange);
            _mainPool.stake(_borrower, _collChange);
        } else {
            _mainPool.unstake(_borrower, _collChange);
            _mainPool.sendCollateral(_depositToken, _borrower, _collChange);
        }
    }

    // Send Collateral from user to this contract and increase its recorded Collateral balance
    function _mainPoolAddColl(IERC20 _depositToken, IMainPool _mainPool, uint _amount) internal {
        
        // transfer tokens from user to mainPool contract
        _depositToken.safeTransferFrom(msg.sender, address(_mainPool), _amount);
        
        _mainPool.increaseCollateral(_amount);
    }

    // Issue the specified amount of UND to _account and increases the total active debt (_netDebtIncrease potentially includes a UNDFee)
    function _withdrawUND(IMainPool _mainPool, IUNDToken _undToken, address _account, uint _UNDAmount, uint _netDebtIncrease) internal {
        _mainPool.increaseUNDDebt(_netDebtIncrease);
        _undToken.mint(_account, _UNDAmount);
    }

    // Burn the specified amount of UND from _account and decreases the total active debt
    function _repayUND(IMainPool _mainPool, IUNDToken _undToken, address _account, uint _UND) internal {
        _mainPool.decreaseUNDDebt(_UND);
        _undToken.burn(_account, _UND);
    }

    // --- 'Require' wrapper functions ---

    function _requireSingularCollChange(uint256 _collDeposit, uint256 _collWithdrawal) internal pure {
        require(_collDeposit == 0 || _collWithdrawal == 0, "BorrowerOperations: Cannot withdraw and add coll");
    }

    function _requireNonZeroAdjustment(uint256 _collDeposit, uint256 _collWithdrawal, uint256 _UNDChange) internal pure {
        require(_collDeposit != 0 || _collWithdrawal != 0 || _UNDChange != 0, "BorrowerOps: There must be either a collateral change or a debt change");
    }

    function _requireICRisAboveMCR(uint _newICR) internal view {
        require(_newICR >= MCR, "BorrowerOps: An operation that would result in ICR < MCR is not permitted");
    }

    function _requireAtLeastMinNetDebt(uint _netDebt) internal pure {
        require (_netDebt >= MIN_NET_DEBT, "BorrowerOps: Account's net debt must be greater than minimum");
    }

    function _requireValidUNDRepayment(uint _currentDebt, uint _debtRepayment) internal pure {
        require(_debtRepayment <= _currentDebt, "BorrowerOps: Amount repaid must not be larger than the Account's debt");
    }

    function _requireValidCollWithdrawal(uint _collWithdraw, uint _currentColl) internal pure {
        require(_collWithdraw <= _currentColl, "BorrowerOps: Account collateral withdraw amount can not be greater than current collateral amount");
    }

    function _requireAccountisActive(IDEAccountManager _accountManager, address _borrower) internal view {
        uint status = _accountManager.getAccountStatus(_borrower);
        require(status == 1, "BorrowerOps: Account does not exist or is closed");
    }

    function _requireSufficientUNDBalance(IUNDToken _undToken, address _borrower, uint _debtRepayment) internal view {
        require(_undToken.balanceOf(_borrower) >= _debtRepayment, "BorrowerOps: Caller doesnt have enough UND to make repayment");
    }

    function _requireAccountisNotActive(IDEAccountManager _accountManager, address _borrower) internal view {
        uint status = _accountManager.getAccountStatus(_borrower);
        require(status != 1, "BorrowerOps: Account is active");
    }

    function _requireUserAcceptsFee(uint _fee, uint _amount, uint _maxFeePercentage) internal pure {
        uint feePercentage = (_fee * DECIMAL_PRECISION) / _amount;
        require(feePercentage <= _maxFeePercentage, "BorrowerOps: Fee exceeded provided maximum");
    }

    function _requireNonZeroDebtChange(uint _UNDChange) internal pure {
        require(_UNDChange > 0, "BorrowerOps: Debt increase requires non-zero debtChange");
    }

    function _requireValidMaxFeePercentage(uint _maxFeePercentage) internal view {
        require(_maxFeePercentage >= BORROWING_FEE_FLOOR() && _maxFeePercentage <= DECIMAL_PRECISION,
            "BorrowerOps: Max fee percentage must be between 0.5% and 100%");
    }

    function _requireMaxUNDMintLimitNotReached(IMainPool _mainPool, uint256 _UNDChange) internal view {
        uint256 currentDebt = getEntireSystemDebt();
        uint256 mintLimit = _mainPool.undMintLimit();
        require(currentDebt + _UNDChange <= mintLimit, "BorrowerOps: UND max mint limit reached");
    }

    // --- ICR getters ---

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewICRFromAccountChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    )
        pure
        internal
        returns (uint)
    {
        (uint newColl, uint newDebt) = _getNewAccountAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);

        uint newICR = UnboundMath._computeCR(newColl, newDebt, _price);
        return newICR;
    }

    function _getNewAccountAmounts(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        internal
        pure
        returns (uint, uint)
    {
        uint newColl = _coll;
        uint newDebt = _debt;

        newColl = _isCollIncrease ? _coll + _collChange :  _coll - _collChange;
        newDebt = _isDebtIncrease ? _debt + _debtChange : _debt - _debtChange;

        return (newColl, newDebt);
    }
}
