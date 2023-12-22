// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

// AccountManager - store records for each accounts collateral debt, & functioanlity for liquidation and redemptions, 

import "./UnboundBase.sol";

import "./IAccountManager.sol";
import "./UniswapV2PriceProvider.sol";

import "./Initializable.sol";

contract AccountManager is UnboundBase, IAccountManager, Initializable{

    address public override borrowerOperations;

    address public override chainLinkRegistry;

    uint256 public override maxPercentDiff;
    uint256 public override allowedDelay;


    address public override governanceFeeAddress;


    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    // Store the necessary data for a account
    struct Account {
        uint debt;
        uint coll;
        Status status;
        uint128 arrayIndex;
    }

    struct ContractsCache {
        IMainPool mainPool;
        IUNDToken undToken;
        ISortedAccounts sortedAccounts;
        ICollSurplusPool collSurplusPool;
        IERC20 depositToken;
        IUnboundFeesFactory unboundFeesFactory;
    }

    /*
    * --- Variable container structs for liquidations ---
    *
    * These structs are used to hold, return and assign variables inside the liquidation functions,
    * in order to avoid the error: "CompilerError: Stack too deep".
    **/

    struct LocalVariables_LiquidationSequence {
        uint i;
        uint ICR;
        address user;
        uint entireSystemDebt;
        uint entireSystemColl;
    }

    struct LiquidationTotals {
        uint totalCollInSequence;
        uint totalDebtInSequence;
        uint totalLiquidationProfit;
        uint totalCollToSendToLiquidator;
    }

    struct LiquidationValues {
        uint accountDebt;
        uint accountColl;
        uint liquidationProfit;
        uint collToSendToLiquidator;
    }

    // --- Variable container structs for redemptions ---

    struct RedemptionTotals {
        uint remainingUND;
        uint totalUNDToRedeem;
        uint totalCollateralDrawn;
        uint CollateralFee;
        uint CollateralToSendToRedeemer;
        uint decayedBaseRate;
        uint price;
        uint totalUNDSupplyAtStart;
    }

    struct SingleRedemptionValues {
        uint UNDLot;
        uint CollateralLot;
        bool cancelledPartial;
    }

    mapping (address => Account) public Accounts;


    // Array of all active account addresses - used to to compute an approximate hint off-chain, for the sorted list insertion
    address[] public AccountOwners;

    function initialize (
        address _feeFactory,
        address _borrowerOperations,
        address _mainPool,
        address _undToken,
        address _sortedAccounts,
        address _collSurplusPool,
        address _depositToken,
        address _chainLinkRegistry,
        uint256 _maxPercentDiff,
        uint256 _allowedDelay,
        address _governanceFeeAddress,
        uint256 _MCR
    ) 
        public 
        initializer
    {
        unboundFeesFactory = IUnboundFeesFactory(_feeFactory);
        borrowerOperations = _borrowerOperations;
        mainPool = IMainPool(_mainPool);
        undToken = IUNDToken(_undToken);
        sortedAccounts = ISortedAccounts(_sortedAccounts);
        depositToken = IERC20(_depositToken);
        collSurplusPool = ICollSurplusPool(_collSurplusPool);
        chainLinkRegistry = _chainLinkRegistry;
        maxPercentDiff = _maxPercentDiff;
        allowedDelay = _allowedDelay;
        governanceFeeAddress = _governanceFeeAddress;
        MCR = _MCR;
    }

    // --- Getters ---

    function getAccountOwnersCount() external view override returns (uint) {
        return AccountOwners.length;
    }

    function getAccountFromAccountOwnersArray(uint _index) external view override returns (address) {
        return AccountOwners[_index];
    }

    // --- Account Liquidation functions ---

    // Single liquidation function. Closes the account if its ICR is lower than the minimum collateral ratio.
    function liquidate(address _borrower) external override {
        _requireAccountIsActive(_borrower);

        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        batchLiquidateAccounts(borrowers);
    }

    // --- Inner single liquidation functions ---

    // Liquidate one account.
    function _liquidate(
        IMainPool _mainPool,
        address _borrower,
        uint _price
    )
        internal
        returns (LiquidationValues memory singleLiquidation)
    {

        singleLiquidation.accountDebt = Accounts[_borrower].debt;
        singleLiquidation.accountColl = Accounts[_borrower].coll;

        uint256 _debtWorthOfColl = (singleLiquidation.accountDebt * DECIMAL_PRECISION) / _price;

        if(singleLiquidation.accountColl > _debtWorthOfColl){  
            singleLiquidation.liquidationProfit = singleLiquidation.accountColl - _debtWorthOfColl;
        }

        singleLiquidation.collToSendToLiquidator = singleLiquidation.accountColl;

        // unstake collateral from farming contract
        _mainPool.unstake(_borrower, singleLiquidation.accountColl);

        _closeAccount(_borrower, Status.closedByLiquidation);
        emit AccountLiquidated(_borrower, singleLiquidation.accountDebt, singleLiquidation.accountColl, AccountManagerOperation.liquidation);
        emit AccountUpdated(_borrower, 0, 0, AccountManagerOperation.liquidation);
        return singleLiquidation;
    }

    /*
    * Liquidate a sequence of accounts. Closes a maximum number of n under-collateralized Accounts,
    * starting from the one with the lowest collateral ratio in the system, and moving upwards
    */
    function liquidateAccounts(uint _n) external override {

        ContractsCache memory contractsCache = ContractsCache(
            mainPool,
            undToken,
            sortedAccounts,
            collSurplusPool,
            depositToken,
            unboundFeesFactory
        );

        LiquidationTotals memory totals;

        // get price of pool token from oracle
        uint256 price = uint256 (UniswapV2PriceProvider.latestAnswer(IAccountManager(address(this))));

        // Perform the appropriate liquidation sequence - tally the values, and obtain their totals
        totals = _getTotalsFromLiquidateAccountsSequence(contractsCache.mainPool, contractsCache.sortedAccounts, price, _n);

        require(totals.totalDebtInSequence > 0, "AccountManager: nothing to liquidate");

        // decrease UND debt and burn UND from user account
        contractsCache.mainPool.decreaseUNDDebt(totals.totalDebtInSequence);
        contractsCache.undToken.burn(msg.sender, totals.totalDebtInSequence);

        // send collateral to liquidator
        contractsCache.mainPool.sendCollateral(contractsCache.depositToken, msg.sender, totals.totalCollToSendToLiquidator);

        emit Liquidation(totals.totalDebtInSequence, totals.totalCollInSequence, totals.totalLiquidationProfit);

    }

    function _getTotalsFromLiquidateAccountsSequence
    (
        IMainPool _mainPool,
        ISortedAccounts _sortedAccounts,
        uint _price,
        uint _n
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;


        for (vars.i = 0; vars.i < _n; vars.i++) {
            vars.user = _sortedAccounts.getLast();
            vars.ICR = getCurrentICR(vars.user, _price);

            if (vars.ICR < MCR) {
                singleLiquidation = _liquidate(_mainPool, vars.user, _price);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

            } else break;  // break if the loop reaches a Account with ICR >= MCR
        }
    }

    /*
    * Attempt to liquidate a custom list of accounts provided by the caller.
    */
    function batchLiquidateAccounts(address[] memory _accountArray) public override {
        require(_accountArray.length != 0, "AccountManager: Calldata address array must not be empty");

        IMainPool mainPoolCached = mainPool;
        IUNDToken undTokenCached = undToken;
        IERC20 depositTokenCached = depositToken;

        LiquidationTotals memory totals;

        // get price of pool token from oracle
        uint256 price = uint256 (UniswapV2PriceProvider.latestAnswer(IAccountManager(address(this))));

        // Perform the appropriate liquidation sequence - tally values and obtain their totals.
        totals = _getTotalsFromBatchLiquidate(mainPoolCached, price, _accountArray);

        require(totals.totalDebtInSequence > 0, "AccountManager: nothing to liquidate");

        // decrease UND debt and burn UND from user account
        mainPoolCached.decreaseUNDDebt(totals.totalDebtInSequence);
        undTokenCached.burn(msg.sender, totals.totalDebtInSequence);

        // send collateral to liquidator
        mainPoolCached.sendCollateral(depositTokenCached, msg.sender, totals.totalCollToSendToLiquidator);

        emit Liquidation(totals.totalDebtInSequence, totals.totalCollInSequence, totals.totalLiquidationProfit);
    }

    function _getTotalsFromBatchLiquidate
    (
        IMainPool _mainPool,
        uint _price,
        address[] memory _accountArray
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;


        for (vars.i = 0; vars.i < _accountArray.length; vars.i++) {
            vars.user = _accountArray[vars.i];
            vars.ICR = getCurrentICR(vars.user, _price);

            if (vars.ICR < MCR) {
                singleLiquidation = _liquidate(_mainPool, vars.user, _price);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
            }
        }
    }

        // --- Liquidation helper functions ---

    function _addLiquidationValuesToTotals(LiquidationTotals memory oldTotals, LiquidationValues memory singleLiquidation)
    internal pure returns(LiquidationTotals memory newTotals) {

        // Tally all the values with their respective running totals
        newTotals.totalDebtInSequence = oldTotals.totalDebtInSequence + singleLiquidation.accountDebt;
        newTotals.totalCollInSequence = oldTotals.totalCollInSequence + singleLiquidation.accountColl;
        newTotals.totalLiquidationProfit = oldTotals.totalLiquidationProfit + singleLiquidation.liquidationProfit;
        newTotals.totalCollToSendToLiquidator = oldTotals.totalCollToSendToLiquidator + singleLiquidation.collToSendToLiquidator;

        return newTotals;
    }

    // --- Redemption functions ---

    // Redeem as much collateral as possible from _borrower's Account in exchange for UND up to _maxUNDamount
    function _redeemCollateralFromAccount(
        ContractsCache memory _contractsCache,
        address _borrower,
        uint _maxUNDamount,
        uint _price,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR
    )
        internal returns (SingleRedemptionValues memory singleRedemption)
    {

        uint256 userCurrentDebt = Accounts[_borrower].debt;
        uint256 userCurrentColl = Accounts[_borrower].coll;

         // Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the Account
        singleRedemption.UNDLot = UnboundMath._min(_maxUNDamount, userCurrentDebt);

        // Get the CollateralLot of equivalent value in USD
        singleRedemption.CollateralLot = (singleRedemption.UNDLot * DECIMAL_PRECISION) / _price;

        // Decrease the debt and collateral of the current Account according to the UND lot and corresponding collateral to send
        uint newDebt = userCurrentDebt - singleRedemption.UNDLot;
        uint newColl = userCurrentColl - singleRedemption.CollateralLot;

        if (newDebt == 0) {
            // unstake collateral from farming contract
            _contractsCache.mainPool.unstake(_borrower, userCurrentColl);
            
            // No debt left in the Account (except for the liquidation reserve), therefore the account gets closed
            _closeAccount(_borrower, Status.closedByRedemption);
            _redeemCloseAccount(_contractsCache, _borrower, newColl);
            emit AccountUpdated(_borrower, 0, 0, AccountManagerOperation.redeemCollateral);

        } else {
            uint newNICR = UnboundMath._computeNominalCR(newColl, newDebt);

            /*
            * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
            * certainly result in running out of gas. 
            *
            * If the resultant net debt of the partial is less than the minimum, net debt we bail.
            */
            if (newNICR != _partialRedemptionHintNICR || newDebt < MIN_NET_DEBT) {
                singleRedemption.cancelledPartial = true;
                return singleRedemption;
            }

            // unstake collateral from farming contract
            _contractsCache.mainPool.unstake(_borrower, singleRedemption.CollateralLot);

            _contractsCache.sortedAccounts.reInsert(_borrower, newNICR, _upperPartialRedemptionHint, _lowerPartialRedemptionHint);
        
            Accounts[_borrower].debt = newDebt;
            Accounts[_borrower].coll = newColl;

            emit AccountUpdated(
                _borrower,
                newDebt, newColl,
                AccountManagerOperation.redeemCollateral
            );
        }

        return singleRedemption;
    }

    /*
    * Called when a full redemption occurs, and closes the account.
    * The redeemer swaps (debt - liquidation reserve) UND for (debt - liquidation reserve) worth of Collateral, so the _redeemCloseAccount liquidation reserve left corresponds to the remaining debt.
    * In order to close the account, the _redeemCloseAccount liquidation reserve is burned, and the corresponding debt is removed from the main pool.
    * The debt recorded on the account's struct is zero'd elswhere, in _closeAccount.
    * Any surplus Collateral left in the account, is sent to the Coll surplus pool, and can be later claimed by the borrower.
    */
    function _redeemCloseAccount(ContractsCache memory _contractsCache, address _borrower, uint _Collateral) internal {
        // send collateral from Main Pool to CollSurplus Pool
        _contractsCache.collSurplusPool.accountSurplus(_borrower, _Collateral);
        _contractsCache.mainPool.sendCollateral(_contractsCache.depositToken, address(_contractsCache.collSurplusPool), _Collateral);
    }


    function _isValidFirstRedemptionHint(ISortedAccounts _sortedAccounts, address _firstRedemptionHint, uint _price) internal view returns (bool) {
        if (_firstRedemptionHint == address(0) ||
            !_sortedAccounts.contains(_firstRedemptionHint) ||
            getCurrentICR(_firstRedemptionHint, _price) < MCR
        ) {
            return false;
        }

        address nextAccount = _sortedAccounts.getNext(_firstRedemptionHint);
        return nextAccount == address(0) || getCurrentICR(nextAccount, _price) < MCR;
    }

    /* Send _UNDamount UND to the system and redeem the corresponding amount of collateral from as many Accounts as are needed to fill the redemption
    * request.
    *
    * Note that if _amount is very large, this function can run out of gas, specially if traversed accounts are small. This can be easily avoided by
    * splitting the total _amount in appropriate chunks and calling the function multiple times.
    *
    * Param `_maxIterations` can also be provided, so the loop through Account is capped (if it’s zero, it will be ignored).This makes it easier to
    * avoid OOG for the frontend, as only knowing approximately the average cost of an iteration is enough, without needing to know the “topology”
    * of the account list. It also avoids the need to set the cap in stone in the contract, nor doing gas calculations, as both gas price and opcode
    * costs can vary.
    *
    * All Accounts that are redeemed from -- with the likely exception of the last one -- will end up with no debt left, therefore they will be closed.
    * If the last Account does have some remaining debt, it has a finite ICR, and the reinsertion could be anywhere in the list, therefore it requires a hint.
    * A frontend should use getRedemptionHints() to calculate what the ICR of this Account will be after redemption, and pass a hint for its position
    * in the sortedAccounts list along with the ICR value that the hint was found for.
    *
    * If another transaction modifies the list between calling getRedemptionHints() and passing the hints to redeemCollateral(), it
    * is very likely that the last (partially) redeemed Account would end up with a different ICR than what the hint is for. In this case the
    * redemption will stop after the last completely redeemed Account and the sender will keep the remaining UND amount, which they can attempt
    * to redeem later.
    */

    function redeemCollateral(
        uint _UNDamount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFeePercentage
    )
        external
        override
    {

        ContractsCache memory contractsCache = ContractsCache(
            mainPool,
            undToken,
            sortedAccounts,
            collSurplusPool,
            depositToken,
            unboundFeesFactory
        );

        RedemptionTotals memory totals;

        _requireValidMaxFeePercentage(_maxFeePercentage);

        // get price of pool token from oracle
        totals.price = uint256 (UniswapV2PriceProvider.latestAnswer(IAccountManager(address(this))));
        _requireAmountGreaterThanZero(_UNDamount);
        _requireUNDBalanceCoversRedemption(contractsCache.undToken, msg.sender, _UNDamount);

        totals.totalUNDSupplyAtStart = contractsCache.undToken.totalSupply();
        // Confirm redeemer's balance is less than total UND supply
        assert(contractsCache.undToken.balanceOf(msg.sender) <= totals.totalUNDSupplyAtStart);

        totals.remainingUND = _UNDamount;
        address currentBorrower;

        if (_isValidFirstRedemptionHint(contractsCache.sortedAccounts, _firstRedemptionHint, totals.price)) {
            currentBorrower = _firstRedemptionHint;
        } else {
            currentBorrower = contractsCache.sortedAccounts.getLast();
            // Find the first account with ICR >= MCR
            while (currentBorrower != address(0) && getCurrentICR(currentBorrower, totals.price) < MCR) {
                currentBorrower = contractsCache.sortedAccounts.getPrev(currentBorrower);
            }
        }

        // Loop through the Accounts starting from the one with lowest collateral ratio until _amount of UND is exchanged for collateral
        if (_maxIterations == 0) { _maxIterations = type(uint256).max; }

        while (currentBorrower != address(0) && totals.remainingUND > 0 && _maxIterations > 0) {
            _maxIterations--;

            // Save the address of the Account preceding the current one, before potentially modifying the list
            address nextUserToCheck = contractsCache.sortedAccounts.getPrev(currentBorrower);

            SingleRedemptionValues memory singleRedemption = _redeemCollateralFromAccount(
                contractsCache,
                currentBorrower,
                totals.remainingUND,
                totals.price,
                _upperPartialRedemptionHint,
                _lowerPartialRedemptionHint,
                _partialRedemptionHintNICR
            );

            if (singleRedemption.cancelledPartial) break; // Partial redemption was cancelled (out-of-date hint, or new net debt < minimum), therefore we could not redeem from the last Account

            totals.totalUNDToRedeem  = totals.totalUNDToRedeem + singleRedemption.UNDLot;
            totals.totalCollateralDrawn = totals.totalCollateralDrawn + singleRedemption.CollateralLot;

            totals.remainingUND = totals.remainingUND - singleRedemption.UNDLot;
            currentBorrower = nextUserToCheck;
        }

        require(totals.totalCollateralDrawn > 0, "AccountManager: Unable to redeem any amount");

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total UND supply value, from before it was reduced by the redemption.
        contractsCache.unboundFeesFactory.updateBaseRateFromRedemption(totals.totalCollateralDrawn, totals.price, totals.totalUNDSupplyAtStart);
    
        // Calculate the Collateral fee
        totals.CollateralFee = contractsCache.unboundFeesFactory.getRedemptionFee(totals.totalCollateralDrawn);
    
        _requireUserAcceptsFee(totals.CollateralFee, totals.totalCollateralDrawn, _maxFeePercentage);
    
        // Send the Collateral fee to the governance fee address
        contractsCache.mainPool.sendCollateral(contractsCache.depositToken, governanceFeeAddress, totals.CollateralFee);

        totals.CollateralToSendToRedeemer = totals.totalCollateralDrawn - totals.CollateralFee;

        emit Redemption(_UNDamount, totals.totalUNDToRedeem, totals.totalCollateralDrawn, totals.CollateralFee);

        // Burn the total UND that is cancelled with debt, and send the redeemed Collateral to msg.sender
        contractsCache.undToken.burn(msg.sender, totals.totalUNDToRedeem);
        // Update Main Pool UND, and send Collateral to account
        contractsCache.mainPool.decreaseUNDDebt(totals.totalUNDToRedeem);
        contractsCache.mainPool.sendCollateral(contractsCache.depositToken, msg.sender, totals.CollateralToSendToRedeemer);
    }

    /**
     * Return Unbound Fees Factory contract address (to validate minter in UND contract)
     */
    function factory() external view returns(address){
        return address(unboundFeesFactory);
    }

    // // --- Account property getters ---

    function getAccountStatus(address _borrower) external override view returns (uint) {
        return uint(Accounts[_borrower].status);
    }

    function getAccountDebt(address _borrower) external view override returns (uint) {
        return Accounts[_borrower].debt;
    }

    function getAccountColl(address _borrower) external view override returns (uint) {
        return Accounts[_borrower].coll;
    }

    // --- Helper functions ---

    // Return the nominal collateral ratio (ICR) of a given Account, without the price. Takes a Account's pending coll and debt rewards from redistributions into account.
    function getNominalICR(address _borrower) public override view returns (uint) {
        (uint currentCollateral, uint currentUNDDebt) = _getCurrentAccountAmounts(_borrower);

        uint NICR = UnboundMath._computeNominalCR(currentCollateral, currentUNDDebt);
        return NICR;
    }

    // Return the current collateral ratio (ICR) of a given Account. Takes a account's pending coll and debt rewards from redistributions into account.
    function getCurrentICR(address _borrower, uint _price) public view override returns (uint) {
        (uint currentCollateral, uint currentUNDDebt) = _getCurrentAccountAmounts(_borrower);

        uint ICR = UnboundMath._computeCR(currentCollateral, currentUNDDebt, _price);
        return ICR;
    }

    // Return the Accounts entire debt and coll
    function getEntireDebtAndColl(
        address _borrower
    )
        public
        view
        override
        returns (uint debt, uint coll)
    {
        debt = Accounts[_borrower].debt;
        coll = Accounts[_borrower].coll;
    }

    function _getCurrentAccountAmounts(address _borrower) internal view returns (uint, uint) {
        uint currentCollateral = Accounts[_borrower].coll;
        uint currentUNDDebt = Accounts[_borrower].debt;

        return (currentCollateral, currentUNDDebt);
    }


    function closeAccount(address _borrower) external override {
        _requireCallerIsBorrowerOperations();
        return _closeAccount(_borrower, Status.closedByOwner);
    }

    function _closeAccount(address _borrower, Status closedStatus) internal {
        assert(closedStatus != Status.nonExistent && closedStatus != Status.active);

        uint AccountOwnersArrayLength = AccountOwners.length;

        Accounts[_borrower].status = closedStatus;
        Accounts[_borrower].coll = 0;
        Accounts[_borrower].debt = 0;

        _removeAccountOwner(_borrower, AccountOwnersArrayLength);
        sortedAccounts.remove(_borrower);

        Accounts[_borrower].arrayIndex = 0;
    }

    // Push the owner's address to the Account owners list, and record the corresponding array index on the Account struct
    function addAccountOwnerToArray(address _borrower) external override returns (uint index) {
        _requireCallerIsBorrowerOperations();
        index = _addAccountOwnerToArray(_borrower);
    }

    function _addAccountOwnerToArray(address _borrower) internal returns (uint128 index) {
        /* Max array size is 2**128 - 1, i.e. ~3e30 accounts. No risk of overflow, since accounts have minimum UND
        debt of liquidation reserve plus MIN_NET_DEBT. 3e30 UND dwarfs the value of all wealth in the world ( which is < 1e15 USD). */

        // Push the AccountOwner to the array
        AccountOwners.push(_borrower);

        // Record the index of the new AccountOwner on their Account struct
        index = uint128(AccountOwners.length - 1);
        Accounts[_borrower].arrayIndex = index;

        return index;
    }
    
    /*
    * Remove a Account owner from the AccountOwners array, not preserving array order. Removing owner 'B' does the following:
    * [A B C D E] => [A E C D], and updates E's Account struct to point to its new array index.
    */
    function _removeAccountOwner(address _borrower, uint AccountOwnersArrayLength) internal {
        Status accountStatus = Accounts[_borrower].status;
        // It’s set in caller function `_closeAccount`
        assert(accountStatus != Status.nonExistent && accountStatus != Status.active);

        uint128 index = Accounts[_borrower].arrayIndex;
        uint length = AccountOwnersArrayLength;
        uint idxLast = length - 1;

        assert(index <= idxLast);

        address addressToMove = AccountOwners[idxLast];

        AccountOwners[index] = addressToMove;
        Accounts[addressToMove].arrayIndex = index;
        emit AccountIndexUpdated(addressToMove, index);

        AccountOwners.pop();
    }

    // --- Account property setters, called by BorrowerOperations ---

    function setAccountStatus(address _borrower, uint _num) external override{
        _requireCallerIsBorrowerOperations();
        Accounts[_borrower].status = Status(_num);
    }

    function increaseAccountColl(address _borrower, uint _collIncrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newColl = Accounts[_borrower].coll + _collIncrease;
        Accounts[_borrower].coll = newColl;
        return newColl;
    }

    function decreaseAccountColl(address _borrower, uint _collDecrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newColl = Accounts[_borrower].coll - _collDecrease;
        Accounts[_borrower].coll = newColl;
        return newColl;
    }

    function increaseAccountDebt(address _borrower, uint _debtIncrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newDebt = Accounts[_borrower].debt + _debtIncrease;
        Accounts[_borrower].debt = newDebt;
        return newDebt;
    }

    function decreaseAccountDebt(address _borrower, uint _debtDecrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newDebt = Accounts[_borrower].debt - _debtDecrease;
        Accounts[_borrower].debt = newDebt;
        return newDebt;
    }

    // --- 'require' wrapper functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperations, "AccountManager: Caller is not the BorrowerOperations contract");
    }

    function _requireAccountIsActive(address _borrower) internal view {
        require(Accounts[_borrower].status == Status.active, "AccountManager: Account does not exist or is closed");
    }

    function _requireUNDBalanceCoversRedemption(IUNDToken _undToken, address _redeemer, uint _amount) internal view {
        require(_undToken.balanceOf(_redeemer) >= _amount, "AccountManager: Requested redemption amount must be <= user's UND token balance");
    }

    function _requireAmountGreaterThanZero(uint _amount) internal pure {
        require(_amount > 0, "AccountManager: Amount must be greater than zero");
    }

    function _requireValidMaxFeePercentage(uint _maxFeePercentage) internal view {
        uint256 redemptionFeeFloor = REDEMPTION_FEE_FLOOR();
        require(_maxFeePercentage >= redemptionFeeFloor && _maxFeePercentage <= DECIMAL_PRECISION,
            "AccountManager: Max fee percentage must be between 0.5% and 100%");
    }

    function _requireUserAcceptsFee(uint _fee, uint _amount, uint _maxFeePercentage) internal pure {
        uint feePercentage = (_fee * DECIMAL_PRECISION) / _amount;
        require(feePercentage <= _maxFeePercentage, "AccountManager: Fee exceeded provided maximum");
    }
}
