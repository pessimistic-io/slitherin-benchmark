// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;
import "./Ownable.sol";
import "./SafeERC20.sol";

import "./IERC3156FlashLender.sol";
import "./IERC3156FlashBorrower.sol";
import "./IBorrowerOperations.sol";
import "./ITroveManager.sol";
import "./ITroveManagerHelpers.sol";
import "./ISLSDToken.sol";
import "./ICollSurplusPool.sol";
import "./ISortedTroves.sol";
import "./IPSYStaking.sol";
import "./IStabilityPoolManager.sol";
import "./PSYBase.sol";
import "./CheckContract.sol";
import "./SafetyTransfer.sol";
import "./Initializable.sol";


contract BorrowerOperations is PSYBase, CheckContract, IBorrowerOperations, IERC3156FlashLender, Initializable {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	string public constant NAME = "BorrowerOperations";
	bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

	// --- Connected contract declarations ---

	ITroveManager public troveManager;

	ITroveManagerHelpers public troveManagerHelpers;

	IStabilityPoolManager stabilityPoolManager;

	address gasPoolAddress;

	ICollSurplusPool collSurplusPool;

	IPSYStaking public PSYStaking;
	address public PSYStakingAddress;
	bool isPSYReady;

	address treasury;

	ISLSDToken public SLSDToken;

	// A doubly linked list of Troves, sorted by their collateral ratios
	ISortedTroves public sortedTroves;

	bool public isInitialized;

	/* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

	struct LocalVariables_adjustTrove {
		address asset;
		uint256 price;
		uint256 collChange;
		uint256 netDebtChange;
		bool isCollIncrease;
		uint256 debt;
		uint256 coll;
		uint256 oldICR;
		uint256 newICR;
		uint256 newTCR;
		uint256 SLSDFee;
		uint256 newDebt;
		uint256 newColl;
		uint256 stake;
	}

	struct LocalVariables_openTrove {
		address asset;
		uint256 price;
		uint256 SLSDFee;
		uint256 netDebt;
		uint256 compositeDebt;
		uint256 ICR;
		uint256 NICR;
		uint256 stake;
		uint256 arrayIndex;
	}

	struct ContractsCache {
		ITroveManager troveManager;
		ITroveManagerHelpers troveManagerHelpers;
		IActivePool activePool;
		ISLSDToken SLSDToken;
	}

	enum BorrowerOperation {
		openTrove,
		closeTrove,
		adjustTrove
	}

	event TroveUpdated(
		address indexed _asset,
		address indexed _borrower,
		uint256 _debt,
		uint256 _coll,
		uint256 stake,
		BorrowerOperation operation
	);

	// --- Dependency setters ---

	function setAddresses(
		address _troveManagerAddress,
		address _troveManagerHelpersAddress,
		address _stabilityPoolManagerAddress,
		address _gasPoolAddress,
		address _collSurplusPoolAddress,
		address _sortedTrovesAddress,
		address _slsdTokenAddress,
		address _PSYStakingAddress,
		address _treasury,
		address _psyParamsAddress
	) external override initializer onlyOwner {
		require(!isInitialized, "Already initialized");
		checkContract(_troveManagerAddress);
		checkContract(_troveManagerHelpersAddress);
		checkContract(_stabilityPoolManagerAddress);
		checkContract(_gasPoolAddress);
		checkContract(_collSurplusPoolAddress);
		checkContract(_sortedTrovesAddress);
		checkContract(_slsdTokenAddress);
		checkContract(_psyParamsAddress);
		isInitialized = true;

		troveManager = ITroveManager(_troveManagerAddress);
		troveManagerHelpers = ITroveManagerHelpers(_troveManagerHelpersAddress);
		stabilityPoolManager = IStabilityPoolManager(_stabilityPoolManagerAddress);
		gasPoolAddress = _gasPoolAddress;
		collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
		sortedTroves = ISortedTroves(_sortedTrovesAddress);
		SLSDToken = ISLSDToken(_slsdTokenAddress);

		if (_PSYStakingAddress != address(0)) {
			checkContract(_PSYStakingAddress);
			PSYStakingAddress = _PSYStakingAddress;
			PSYStaking = IPSYStaking(_PSYStakingAddress);
			isPSYReady = true;
		} else {
			changeTreasuryAddress(_treasury);	
		}

		setPSYParameters(_psyParamsAddress);

		emit TroveManagerAddressChanged(_troveManagerAddress);
		emit StabilityPoolAddressChanged(_stabilityPoolManagerAddress);
		emit GasPoolAddressChanged(_gasPoolAddress);
		emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
		emit SortedTrovesAddressChanged(_sortedTrovesAddress);
		emit SLSDTokenAddressChanged(_slsdTokenAddress);
		emit PSYStakingAddressChanged(_PSYStakingAddress);
	}

	// --- Borrower Trove Operations Getter functions ---

	function isContractBorrowerOps() public pure returns (bool) {
		return true;
	}

	// --- Borrower Trove Operations ---

	function openTrove(
		address _asset,
		uint256 _tokenAmount,
		uint256 _maxFeePercentage,
		uint256 _SLSDamount,
		address _upperHint,
		address _lowerHint
	) external payable override {
		
		psyParams.sanitizeParameters(_asset);

		ContractsCache memory contractsCache = ContractsCache(
			troveManager,
			troveManagerHelpers,
			psyParams.activePool(),
			SLSDToken
		);
		LocalVariables_openTrove memory vars;
		vars.asset = _asset;

		_tokenAmount = getMethodValue(vars.asset, _tokenAmount, false);
		vars.price = psyParams.priceFeed().fetchPrice(vars.asset);

		bool isRecoveryMode = _checkRecoveryMode(vars.asset, vars.price);

		_requireValidMaxFeePercentage(vars.asset, _maxFeePercentage, isRecoveryMode);
		_requireTroveisNotActive(
			vars.asset,
			contractsCache.troveManager,
			contractsCache.troveManagerHelpers,
			msg.sender
		);

		vars.netDebt = _SLSDamount;

		if (!isRecoveryMode) {
			vars.SLSDFee = _triggerBorrowingFee(
				vars.asset,
				contractsCache.troveManager,
				contractsCache.troveManagerHelpers,
				contractsCache.SLSDToken,
				_SLSDamount,
				_maxFeePercentage
			);
			vars.netDebt = vars.netDebt.add(vars.SLSDFee);
		}

		_requireAtLeastMinNetDebt(vars.asset, vars.netDebt);

		// ICR is based on the composite debt, i.e. the requested SLSD amount + SLSD borrowing fee + SLSD gas comp.
		vars.compositeDebt = _getCompositeDebt(vars.asset, vars.netDebt);
		assert(vars.compositeDebt > 0);

		vars.ICR = PSYMath._computeCR(_tokenAmount, vars.compositeDebt, vars.price);
		vars.NICR = PSYMath._computeNominalCR(_tokenAmount, vars.compositeDebt);

		if (isRecoveryMode) {
			_requireICRisAboveCCR(vars.asset, vars.ICR);
		} else {
			_requireICRisAboveMCR(vars.asset, vars.ICR);
			uint256 newTCR = _getNewTCRFromTroveChange(
				vars.asset,
				_tokenAmount,
				true,
				vars.compositeDebt,
				true,
				vars.price
			); // bools: coll increase, debt increase
			_requireNewTCRisAboveCCR(vars.asset, newTCR);
		}

		// Set the trove struct's properties
		contractsCache.troveManagerHelpers.setTroveStatus(vars.asset, msg.sender, 1);
		contractsCache.troveManagerHelpers.increaseTroveColl(vars.asset, msg.sender, _tokenAmount);
		contractsCache.troveManagerHelpers.increaseTroveDebt(
			vars.asset,
			msg.sender,
			vars.compositeDebt
		);

		contractsCache.troveManagerHelpers.updateTroveRewardSnapshots(vars.asset, msg.sender);
		vars.stake = contractsCache.troveManagerHelpers.updateStakeAndTotalStakes(
			vars.asset,
			msg.sender
		);

		sortedTroves.insert(vars.asset, msg.sender, vars.NICR, _upperHint, _lowerHint);
		vars.arrayIndex = contractsCache.troveManagerHelpers.addTroveOwnerToArray(
			vars.asset,
			msg.sender
		);
		emit TroveCreated(vars.asset, msg.sender, vars.arrayIndex);

		// Move the ether to the Active Pool, and mint the SLSDAmount to the borrower
		_activePoolAddColl(vars.asset, contractsCache.activePool, _tokenAmount);
		_withdrawSLSD(
			vars.asset,
			contractsCache.activePool,
			contractsCache.SLSDToken,
			msg.sender,
			_SLSDamount,
			vars.netDebt
		);
		// Move the SLSD gas compensation to the Gas Pool
		_withdrawSLSD(
			vars.asset,
			contractsCache.activePool,
			contractsCache.SLSDToken,
			gasPoolAddress,
			psyParams.SLSD_GAS_COMPENSATION(vars.asset),
			psyParams.SLSD_GAS_COMPENSATION(vars.asset)
		);

		emit TroveUpdated(
			vars.asset,
			msg.sender,
			vars.compositeDebt,
			_tokenAmount,
			vars.stake,
			BorrowerOperation.openTrove
		);
		emit SLSDBorrowingFeePaid(vars.asset, msg.sender, vars.SLSDFee);
	}

	// Send ETH as collateral to a trove
	function addColl(
		address _asset,
		uint256 _assetSent,
		address _upperHint,
		address _lowerHint
	) external payable override {
		_adjustTrove(
			_asset,
			getMethodValue(_asset, _assetSent, false),
			msg.sender,
			0,
			0,
			false,
			_upperHint,
			_lowerHint,
			0
		);
	}

	// Send ETH as collateral to a trove. Called by only the Stability Pool.
	function moveETHGainToTrove(
		address _asset,
		uint256 _amountMoved,
		address _borrower,
		address _upperHint,
		address _lowerHint
	) external payable override {
		_requireCallerIsStabilityPool();
		_adjustTrove(
			_asset,
			getMethodValue(_asset, _amountMoved, false),
			_borrower,
			0,
			0,
			false,
			_upperHint,
			_lowerHint,
			0
		);
	}

	// Withdraw ETH collateral from a trove
	function withdrawColl(
		address _asset,
		uint256 _collWithdrawal,
		address _upperHint,
		address _lowerHint
	) external override {
		_adjustTrove(_asset, 0, msg.sender, _collWithdrawal, 0, false, _upperHint, _lowerHint, 0);
	}

	// Withdraw SLSD tokens from a trove: mint new SLSD tokens to the owner, and increase the trove's debt accordingly
	function withdrawSLSD(
		address _asset,
		uint256 _maxFeePercentage,
		uint256 _SLSDamount,
		address _upperHint,
		address _lowerHint
	) external override {
		_adjustTrove(
			_asset,
			0,
			msg.sender,
			0,
			_SLSDamount,
			true,
			_upperHint,
			_lowerHint,
			_maxFeePercentage
		);
	}

	// Repay SLSD tokens to a Trove: Burn the repaid SLSD tokens, and reduce the trove's debt accordingly
	function repaySLSD(
		address _asset,
		uint256 _SLSDamount,
		address _upperHint,
		address _lowerHint
	) external override {
		_adjustTrove(_asset, 0, msg.sender, 0, _SLSDamount, false, _upperHint, _lowerHint, 0);
	}

	function adjustTrove(
		address _asset,
		uint256 _assetSent,
		uint256 _maxFeePercentage,
		uint256 _collWithdrawal,
		uint256 _SLSDChange,
		bool _isDebtIncrease,
		address _upperHint,
		address _lowerHint
	) external payable override {
		_adjustTrove(
			_asset,
			getMethodValue(_asset, _assetSent, true),
			msg.sender,
			_collWithdrawal,
			_SLSDChange,
			_isDebtIncrease,
			_upperHint,
			_lowerHint,
			_maxFeePercentage
		);
	}

	/*
	 * _adjustTrove(): Alongside a debt change, this function can perform either a collateral top-up or a collateral withdrawal.
	 *
	 * It therefore expects either a positive msg.value, or a positive _collWithdrawal argument.
	 *
	 * If both are positive, it will revert.
	 */
	function _adjustTrove(
		address _asset,
		uint256 _assetSent,
		address _borrower,
		uint256 _collWithdrawal,
		uint256 _SLSDChange,
		bool _isDebtIncrease,
		address _upperHint,
		address _lowerHint,
		uint256 _maxFeePercentage
	) internal {
		ContractsCache memory contractsCache = ContractsCache(
			troveManager,
			troveManagerHelpers,
			psyParams.activePool(),
			SLSDToken
		);
		LocalVariables_adjustTrove memory vars;
		vars.asset = _asset;

		require(
			msg.value == 0 || msg.value == _assetSent,
			"BorrowerOp: _AssetSent and Msg.value aren't the same!"
		);

		vars.price = psyParams.priceFeed().fetchPrice(vars.asset);
		bool isRecoveryMode = _checkRecoveryMode(vars.asset, vars.price);

		if (_isDebtIncrease) {
			_requireValidMaxFeePercentage(vars.asset, _maxFeePercentage, isRecoveryMode);
			_requireNonZeroDebtChange(_SLSDChange);
		}
		_requireSingularCollChange(_collWithdrawal, _assetSent);
		_requireNonZeroAdjustment(_collWithdrawal, _SLSDChange, _assetSent);
		_requireTroveisActive(vars.asset, contractsCache.troveManagerHelpers, _borrower);

		// Confirm the operation is either a borrower adjusting their own trove, or a pure ETH transfer from the Stability Pool to a trove
		assert(
			msg.sender == _borrower ||
				(stabilityPoolManager.isStabilityPool(msg.sender) &&
					_assetSent > 0 &&
					_SLSDChange == 0)
		);

		contractsCache.troveManagerHelpers.applyPendingRewards(vars.asset, _borrower);

		// Get the collChange based on whether or not ETH was sent in the transaction
		(vars.collChange, vars.isCollIncrease) = _getCollChange(_assetSent, _collWithdrawal);

		vars.netDebtChange = _SLSDChange;

		// If the adjustment incorporates a debt increase and system is in Normal Mode, then trigger a borrowing fee
		if (_isDebtIncrease && !isRecoveryMode) {
			vars.SLSDFee = _triggerBorrowingFee(
				vars.asset,
				contractsCache.troveManager,
				contractsCache.troveManagerHelpers,
				contractsCache.SLSDToken,
				_SLSDChange,
				_maxFeePercentage
			);
			vars.netDebtChange = vars.netDebtChange.add(vars.SLSDFee); // The raw debt change includes the fee
		}

		vars.debt = contractsCache.troveManagerHelpers.getTroveDebt(vars.asset, _borrower);
		vars.coll = contractsCache.troveManagerHelpers.getTroveColl(vars.asset, _borrower);

		// Get the trove's old ICR before the adjustment, and what its new ICR will be after the adjustment
		vars.oldICR = PSYMath._computeCR(vars.coll, vars.debt, vars.price);
		vars.newICR = _getNewICRFromTroveChange(
			vars.coll,
			vars.debt,
			vars.collChange,
			vars.isCollIncrease,
			vars.netDebtChange,
			_isDebtIncrease,
			vars.price
		);
		require(
			_collWithdrawal <= vars.coll,
			"BorrowerOp: Trying to remove more than the trove holds"
		);

		// Check the adjustment satisfies all conditions for the current system mode
		_requireValidAdjustmentInCurrentMode(
			vars.asset,
			isRecoveryMode,
			_collWithdrawal,
			_isDebtIncrease,
			vars
		);

		// When the adjustment is a debt repayment, check it's a valid amount and that the caller has enough SLSD
		if (!_isDebtIncrease && _SLSDChange > 0) {
			_requireAtLeastMinNetDebt(
				vars.asset,
				_getNetDebt(vars.asset, vars.debt).sub(vars.netDebtChange)
			);
			_requireValidSLSDRepayment(vars.asset, vars.debt, vars.netDebtChange);
			_requireSufficientSLSDBalance(contractsCache.SLSDToken, _borrower, vars.netDebtChange);
		}

		(vars.newColl, vars.newDebt) = _updateTroveFromAdjustment(
			vars.asset,
			contractsCache.troveManager,
			contractsCache.troveManagerHelpers,
			_borrower,
			vars.collChange,
			vars.isCollIncrease,
			vars.netDebtChange,
			_isDebtIncrease
		);
		vars.stake = contractsCache.troveManagerHelpers.updateStakeAndTotalStakes(
			vars.asset,
			_borrower
		);

		// Re-insert trove in to the sorted list
		uint256 newNICR = _getNewNominalICRFromTroveChange(
			vars.coll,
			vars.debt,
			vars.collChange,
			vars.isCollIncrease,
			vars.netDebtChange,
			_isDebtIncrease
		);
		sortedTroves.reInsert(vars.asset, _borrower, newNICR, _upperHint, _lowerHint);

		emit TroveUpdated(
			vars.asset,
			_borrower,
			vars.newDebt,
			vars.newColl,
			vars.stake,
			BorrowerOperation.adjustTrove
		);
		emit SLSDBorrowingFeePaid(vars.asset, msg.sender, vars.SLSDFee);

		// Use the unmodified _SLSDChange here, as we don't send the fee to the user
		_moveTokensAndETHfromAdjustment(
			vars.asset,
			contractsCache.activePool,
			contractsCache.SLSDToken,
			msg.sender,
			vars.collChange,
			vars.isCollIncrease,
			_SLSDChange,
			_isDebtIncrease,
			vars.netDebtChange
		);
	}

	function closeTrove(address _asset) external override {
		ITroveManagerHelpers troveManagerHelpersCached = troveManagerHelpers;
		IActivePool activePoolCached = psyParams.activePool();
		ISLSDToken SLSDTokenCached = SLSDToken;

		_requireTroveisActive(_asset, troveManagerHelpersCached, msg.sender);
		uint256 price = psyParams.priceFeed().fetchPrice(_asset);
		_requireNotInRecoveryMode(_asset, price);

		troveManagerHelpersCached.applyPendingRewards(_asset, msg.sender);

		uint256 coll = troveManagerHelpersCached.getTroveColl(_asset, msg.sender);
		uint256 debt = troveManagerHelpersCached.getTroveDebt(_asset, msg.sender);

		_requireSufficientSLSDBalance(
			SLSDTokenCached,
			msg.sender,
			debt.sub(psyParams.SLSD_GAS_COMPENSATION(_asset))
		);

		uint256 newTCR = _getNewTCRFromTroveChange(_asset, coll, false, debt, false, price);
		_requireNewTCRisAboveCCR(_asset, newTCR);

		troveManagerHelpersCached.removeStake(_asset, msg.sender);
		troveManagerHelpersCached.closeTrove(_asset, msg.sender);

		emit TroveUpdated(_asset, msg.sender, 0, 0, 0, BorrowerOperation.closeTrove);

		// Burn the repaid SLSD from the user's balance and the gas compensation from the Gas Pool
		_repaySLSD(
			_asset,
			activePoolCached,
			SLSDTokenCached,
			msg.sender,
			debt.sub(psyParams.SLSD_GAS_COMPENSATION(_asset))
		);

		_repaySLSD(
			_asset,
			activePoolCached,
			SLSDTokenCached,
			gasPoolAddress,
			psyParams.SLSD_GAS_COMPENSATION(_asset)
		);

		// Send the collateral back to the user
		activePoolCached.sendAsset(_asset, msg.sender, coll);
	}

	/**
	 * Claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode
	 */
	function claimCollateral(address _asset) external override {
		// send ETH from CollSurplus Pool to owner
		collSurplusPool.claimColl(_asset, msg.sender);
	}

	/*
	 * Add PSY token modules later if it is not added at launch
	 */
	function addPSYModules(address _PSYStakingAddress) external onlyOwner {
		require(!isPSYReady,"PSY modules already registered");
		PSYStakingAddress = _PSYStakingAddress;
		PSYStaking = IPSYStaking(_PSYStakingAddress);
		isPSYReady = true;
	}

	/*
	 * Add treasury address who receives fees until PSY modules get registered
	 */
	function changeTreasuryAddress(address _treasury) public onlyOwner {
		require(_treasury != address(0), "Treasury address is zero");
		treasury = _treasury;
		emit TreasuryAddressChanged(_treasury);
	}

	// --- Flashloan functions ---
	    

    /**
     * @dev Loan `amount` tokens to `receiver`, and takes it back plus a `flashFee` after the callback.
     * @param _receiver The contract receiving the tokens, needs to implement the `onFlashLoan(address user, uint256 amount, uint256 fee, bytes calldata)` interface.
     * @param _token The loan currency.
     * @param _amount The amount of tokens lent.
     * @param _data A data parameter to be passed on to the `receiver` for any custom use.
     */
    function flashLoan(
        IERC3156FlashBorrower _receiver,
        address _token,
        uint256 _amount,
        bytes calldata _data
    ) external override returns(bool) {
        uint256 _supplyBefore = SLSDToken.totalSupply();
		SLSDToken.mint(address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF), address(_receiver), _amount);
        require(
            _receiver.onFlashLoan(msg.sender, address(SLSDToken), _amount, 0, _data) == CALLBACK_SUCCESS,
            "FlashLoan: Callback failed"
        );
		SLSDToken.burn(address(_receiver), _amount);
		uint256 _supplyAfter = SLSDToken.totalSupply();
        require(
            _supplyAfter == _supplyBefore,
            "FlashLoan: Repay failed"
        );
        return true;
    }

    /**
     * @dev The fee to be charged for a given loan.
 	 * 	@param _token The loan currency.
     * @param _amount The amount of tokens len
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(
        address _token,
        uint256 _amount
    ) external view override returns (uint256) {
        return 0;
    }

    /**
     * @dev The amount of currency available to be lent.
     * @param _token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(
        address _token
    ) external view override returns (uint256) {
        if (_token == address(SLSDToken)) {
        	return type(uint256).max - SLSDToken.totalSupply();
    	}
	    return 0;
    }

	// --- Helper functions ---

	function _triggerBorrowingFee(
		address _asset,
		ITroveManager _troveManager,
		ITroveManagerHelpers _troveManagerHelpers,
		ISLSDToken _SLSDToken,
		uint256 _SLSDamount,
		uint256 _maxFeePercentage
	) internal returns (uint256) {
		_troveManagerHelpers.decayBaseRateFromBorrowing(_asset); // decay the baseRate state variable
		uint256 SLSDFee = _troveManagerHelpers.getBorrowingFee(_asset, _SLSDamount);

		_requireUserAcceptsFee(SLSDFee, _SLSDamount, _maxFeePercentage);

		// Send fee to PSY staking contract
		if (isPSYReady) {
			_SLSDToken.mint(_asset, PSYStakingAddress, SLSDFee);
			PSYStaking.increaseF_SLSD(SLSDFee);
		} else {
			_SLSDToken.mint(_asset, treasury, SLSDFee);
		}
		
		return SLSDFee;
	}

	function _getCollChange(uint256 _collReceived, uint256 _requestedCollWithdrawal)
		internal
		pure
		returns (uint256 collChange, bool isCollIncrease)
	{
		if (_collReceived != 0) {
			collChange = _collReceived;
			isCollIncrease = true;
		} else {
			collChange = _requestedCollWithdrawal;
		}
	}

	// Update trove's coll and debt based on whether they increase or decrease
	function _updateTroveFromAdjustment(
		address _asset,
		ITroveManager _troveManager,
		ITroveManagerHelpers _troveManagerHelpers,
		address _borrower,
		uint256 _collChange,
		bool _isCollIncrease,
		uint256 _debtChange,
		bool _isDebtIncrease
	) internal returns (uint256, uint256) {
		uint256 newColl = (_isCollIncrease)
			? _troveManagerHelpers.increaseTroveColl(_asset, _borrower, _collChange)
			: _troveManagerHelpers.decreaseTroveColl(_asset, _borrower, _collChange);
		uint256 newDebt = (_isDebtIncrease)
			? _troveManagerHelpers.increaseTroveDebt(_asset, _borrower, _debtChange)
			: _troveManagerHelpers.decreaseTroveDebt(_asset, _borrower, _debtChange);

		return (newColl, newDebt);
	}

	function _moveTokensAndETHfromAdjustment(
		address _asset,
		IActivePool _activePool,
		ISLSDToken _SLSDToken,
		address _borrower,
		uint256 _collChange,
		bool _isCollIncrease,
		uint256 _SLSDChange,
		bool _isDebtIncrease,
		uint256 _netDebtChange
	) internal {
		if (_isDebtIncrease) {
			_withdrawSLSD(_asset, _activePool, _SLSDToken, _borrower, _SLSDChange, _netDebtChange);
		} else {
			_repaySLSD(_asset, _activePool, _SLSDToken, _borrower, _SLSDChange);
		}

		if (_isCollIncrease) {
			_activePoolAddColl(_asset, _activePool, _collChange);
		} else {
			_activePool.sendAsset(_asset, _borrower, _collChange);
		}
	}

	// Send ETH to Active Pool and increase its recorded ETH balance
	function _activePoolAddColl(
		address _asset,
		IActivePool _activePool,
		uint256 _amount
	) internal {
		if (_asset == ETH_REF_ADDRESS) {
			(bool success, ) = address(_activePool).call{ value: _amount }("");
			require(success, "BorrowerOps: Sending ETH to ActivePool failed");
		} else {
			IERC20(_asset).safeTransferFrom(
				msg.sender,
				address(_activePool),
				SafetyTransfer.decimalsCorrection(_asset, _amount)
			);

			_activePool.receivedERC20(_asset, _amount);
		}
	}

	// Issue the specified amount of SLSD to _account and increases the total active debt (_netDebtIncrease potentially includes a SLSDFee)
	function _withdrawSLSD(
		address _asset,
		IActivePool _activePool,
		ISLSDToken _SLSDToken,
		address _account,
		uint256 _SLSDamount,
		uint256 _netDebtIncrease
	) internal {
		_activePool.increaseSLSDDebt(_asset, _netDebtIncrease);
		_SLSDToken.mint(_asset, _account, _SLSDamount);
	}

	// Burn the specified amount of SLSD from _account and decreases the total active debt
	function _repaySLSD(
		address _asset,
		IActivePool _activePool,
		ISLSDToken _SLSDToken,
		address _account,
		uint256 _SLSD
	) internal {
		_activePool.decreaseSLSDDebt(_asset, _SLSD);
		_SLSDToken.burn(_account, _SLSD);
	}

	// --- 'Require' wrapper functions ---

	function _requireSingularCollChange(uint256 _collWithdrawal, uint256 _amountSent)
		internal
		view
	{
		require(
			_collWithdrawal == 0 || _amountSent == 0,
			"BorrowerOperations: Cannot withdraw and add coll"
		);
	}

	function _requireNonZeroAdjustment(
		uint256 _collWithdrawal,
		uint256 _SLSDChange,
		uint256 _assetSent
	) internal view {
		require(
			msg.value != 0 || _collWithdrawal != 0 || _SLSDChange != 0 || _assetSent != 0,
			"BorrowerOps: There must be either a collateral change or a debt change"
		);
	}

	function _requireTroveisActive(
		address _asset,
		ITroveManagerHelpers _troveManagerHelpers,
		address _borrower
	) internal view {
		uint256 status = _troveManagerHelpers.getTroveStatus(_asset, _borrower);
		require(status == 1, "BorrowerOps: Trove does not exist or is closed");
	}

	function _requireTroveisNotActive(
		address _asset,
		ITroveManager _troveManager,
		ITroveManagerHelpers _troveManagerHelpers,
		address _borrower
	) internal view {
		uint256 status = _troveManagerHelpers.getTroveStatus(_asset, _borrower);
		require(status != 1, "BorrowerOps: Trove is active");
	}

	function _requireNonZeroDebtChange(uint256 _SLSDChange) internal pure {
		require(_SLSDChange > 0, "BorrowerOps: Debt increase requires non-zero debtChange");
	}

	function _requireNotInRecoveryMode(address _asset, uint256 _price) internal view {
		require(
			!_checkRecoveryMode(_asset, _price),
			"BorrowerOps: Operation not permitted during Recovery Mode"
		);
	}

	function _requireNoCollWithdrawal(uint256 _collWithdrawal) internal pure {
		require(
			_collWithdrawal == 0,
			"BorrowerOps: Collateral withdrawal not permitted Recovery Mode"
		);
	}

	function _requireValidAdjustmentInCurrentMode(
		address _asset,
		bool _isRecoveryMode,
		uint256 _collWithdrawal,
		bool _isDebtIncrease,
		LocalVariables_adjustTrove memory _vars
	) internal view {
		/*
		 *In Recovery Mode, only allow:
		 *
		 * - Pure collateral top-up
		 * - Pure debt repayment
		 * - Collateral top-up with debt repayment
		 * - A debt increase combined with a collateral top-up which makes the ICR >= 150% and improves the ICR (and by extension improves the TCR).
		 *
		 * In Normal Mode, ensure:
		 *
		 * - The new ICR is above MCR
		 * - The adjustment won't pull the TCR below CCR
		 */
		if (_isRecoveryMode) {
			_requireNoCollWithdrawal(_collWithdrawal);
			if (_isDebtIncrease) {
				_requireICRisAboveCCR(_asset, _vars.newICR);
				_requireNewICRisAboveOldICR(_vars.newICR, _vars.oldICR);
			}
		} else {
			// if Normal Mode
			_requireICRisAboveMCR(_asset, _vars.newICR);
			_vars.newTCR = _getNewTCRFromTroveChange(
				_asset,
				_vars.collChange,
				_vars.isCollIncrease,
				_vars.netDebtChange,
				_isDebtIncrease,
				_vars.price
			);
			_requireNewTCRisAboveCCR(_asset, _vars.newTCR);
		}
	}

	function _requireICRisAboveMCR(address _asset, uint256 _newICR) internal view {
		require(
			_newICR >= psyParams.MCR(_asset),
			"BorrowerOps: An operation that would result in ICR < MCR is not permitted"
		);
	}

	function _requireICRisAboveCCR(address _asset, uint256 _newICR) internal view {
		require(
			_newICR >= psyParams.CCR(_asset),
			"BorrowerOps: Operation must leave trove with ICR >= CCR"
		);
	}

	function _requireNewICRisAboveOldICR(uint256 _newICR, uint256 _oldICR) internal pure {
		require(
			_newICR >= _oldICR,
			"BorrowerOps: Cannot decrease your Trove's ICR in Recovery Mode"
		);
	}

	function _requireNewTCRisAboveCCR(address _asset, uint256 _newTCR) internal view {
		require(
			_newTCR >= psyParams.CCR(_asset),
			"BorrowerOps: An operation that would result in TCR < CCR is not permitted"
		);
	}

	function _requireAtLeastMinNetDebt(address _asset, uint256 _netDebt) internal view {
		require(
			_netDebt >= psyParams.MIN_NET_DEBT(_asset),
			"BorrowerOps: Trove's net debt must be greater than minimum"
		);
	}

	function _requireValidSLSDRepayment(
		address _asset,
		uint256 _currentDebt,
		uint256 _debtRepayment
	) internal view {
		require(
			_debtRepayment <= _currentDebt.sub(psyParams.SLSD_GAS_COMPENSATION(_asset)),
			"BorrowerOps: Amount repaid must not be larger than the Trove's debt"
		);
	}

	function _requireCallerIsStabilityPool() internal view {
		require(
			stabilityPoolManager.isStabilityPool(msg.sender),
			"BorrowerOps: Caller is not Stability Pool"
		);
	}

	function _requireSufficientSLSDBalance(
		ISLSDToken _SLSDToken,
		address _borrower,
		uint256 _debtRepayment
	) internal view {
		require(
			_SLSDToken.balanceOf(_borrower) >= _debtRepayment,
			"BorrowerOps: Caller doesnt have enough SLSD to make repayment"
		);
	}

	function _requireValidMaxFeePercentage(
		address _asset,
		uint256 _maxFeePercentage,
		bool _isRecoveryMode
	) internal view {
		if (_isRecoveryMode) {
			require(
				_maxFeePercentage <= psyParams.DECIMAL_PRECISION(),
				"Max fee percentage must less than or equal to 100%"
			);
		} else {
			require(
				_maxFeePercentage >= psyParams.BORROWING_FEE_FLOOR(_asset) &&
					_maxFeePercentage <= psyParams.DECIMAL_PRECISION(),
				"Max fee percentage must be between 0.5% and 100%"
			);
		}
	}

	// --- ICR and TCR getters ---

	// Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
	function _getNewNominalICRFromTroveChange(
		uint256 _coll,
		uint256 _debt,
		uint256 _collChange,
		bool _isCollIncrease,
		uint256 _debtChange,
		bool _isDebtIncrease
	) internal pure returns (uint256) {
		(uint256 newColl, uint256 newDebt) = _getNewTroveAmounts(
			_coll,
			_debt,
			_collChange,
			_isCollIncrease,
			_debtChange,
			_isDebtIncrease
		);

		uint256 newNICR = PSYMath._computeNominalCR(newColl, newDebt);
		return newNICR;
	}

	// Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
	function _getNewICRFromTroveChange(
		uint256 _coll,
		uint256 _debt,
		uint256 _collChange,
		bool _isCollIncrease,
		uint256 _debtChange,
		bool _isDebtIncrease,
		uint256 _price
	) internal pure returns (uint256) {
		(uint256 newColl, uint256 newDebt) = _getNewTroveAmounts(
			_coll,
			_debt,
			_collChange,
			_isCollIncrease,
			_debtChange,
			_isDebtIncrease
		);

		uint256 newICR = PSYMath._computeCR(newColl, newDebt, _price);
		return newICR;
	}

	function _getNewTroveAmounts(
		uint256 _coll,
		uint256 _debt,
		uint256 _collChange,
		bool _isCollIncrease,
		uint256 _debtChange,
		bool _isDebtIncrease
	) internal pure returns (uint256, uint256) {
		uint256 newColl = _coll;
		uint256 newDebt = _debt;

		newColl = _isCollIncrease ? _coll.add(_collChange) : _coll.sub(_collChange);
		newDebt = _isDebtIncrease ? _debt.add(_debtChange) : _debt.sub(_debtChange);

		return (newColl, newDebt);
	}

	function _getNewTCRFromTroveChange(
		address _asset,
		uint256 _collChange,
		bool _isCollIncrease,
		uint256 _debtChange,
		bool _isDebtIncrease,
		uint256 _price
	) internal view returns (uint256) {
		uint256 totalColl = getEntireSystemColl(_asset);
		uint256 totalDebt = getEntireSystemDebt(_asset);

		totalColl = _isCollIncrease ? totalColl.add(_collChange) : totalColl.sub(_collChange);
		totalDebt = _isDebtIncrease ? totalDebt.add(_debtChange) : totalDebt.sub(_debtChange);

		uint256 newTCR = PSYMath._computeCR(totalColl, totalDebt, _price);
		return newTCR;
	}

	function getCompositeDebt(address _asset, uint256 _debt)
		external
		view
		override
		returns (uint256)
	{
		return _getCompositeDebt(_asset, _debt);
	}

	function getMethodValue(
		address _asset,
		uint256 _amount,
		bool canBeZero
	) private view returns (uint256) {
		bool isEth = _asset == address(0);

		require(
			(canBeZero || (isEth && msg.value != 0)) || (!isEth && msg.value == 0),
			"BorrowerOp: Invalid Input. Override msg.value only if using ETH asset, otherwise use _tokenAmount"
		);

		if (_asset == address(0)) {
			_amount = msg.value;
		}

		return _amount;
	}
}

