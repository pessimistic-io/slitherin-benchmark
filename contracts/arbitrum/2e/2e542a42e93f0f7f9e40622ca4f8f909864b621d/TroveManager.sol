// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "./ITroveManager.sol";
import "./VestaBase.sol";
import "./CheckContract.sol";

error NoBorrowerOperations();

contract TroveManager is VestaBase, CheckContract, ITroveManager {
	using SafeMathUpgradeable for uint256;
	string public constant NAME = "TroveManager";

	// --- Connected contract declarations ---

	address public borrowerOperationsAddress;

	IStabilityPoolManager public stabilityPoolManager;

	address public gasPoolAddress;

	ICollSurplusPool public collSurplusPool;

	IYOUStaking public youStaking;

	IUToken public override uToken;

	// A doubly linked list of Troves, sorted by their sorted by their collateral ratios
	ISortedTroves public sortedTroves;

	// --- Data structures ---

	uint256 public constant SECONDS_IN_ONE_MINUTE = 60;
	/*
	 * Half-life of 12h. 12h = 720 min
	 * (1/2) = d^720 => d = (1/2)^(1/720)
	 */
	uint256 public constant MINUTE_DECAY_FACTOR = 999037758833783000;

	mapping(address => uint256) public baseRate;

	// The timestamp of the latest fee operation (redemption or new U issuance)
	mapping(address => uint256) public lastFeeOperationTime;

	mapping(address => mapping(address => Trove)) public Troves;

	mapping(address => uint256) public totalStakes;

	// Snapshot of the value of totalStakes, taken immediately after the latest liquidation
	mapping(address => uint256) public totalStakesSnapshot;

	// Snapshot of the total collateral across the ActivePool and DefaultPool, immediately after the latest liquidation.
	mapping(address => uint256) public totalCollateralSnapshot;

	/*
	 * L_ETH and L_UDebt track the sums of accumulated liquidation rewards per unit staked. During its lifetime, each stake earns:
	 *
	 * An ETH gain of ( stake * [L_ETH - L_ETH(0)] )
	 * A UDebt increase  of ( stake * [L_UDebt - L_UDebt(0)] )
	 *
	 * Where L_ETH(0) and L_UDebt(0) are snapshots of L_ETH and L_UDebt for the active Trove taken at the instant the stake was made
	 */
	mapping(address => uint256) public L_ASSETS;
	mapping(address => uint256) public L_UDebts;

	// Map addresses with active troves to their RewardSnapshot
	mapping(address => mapping(address => RewardSnapshot)) public rewardSnapshots;

	// Object containing the ETH and U snapshots for a given active trove
	struct RewardSnapshot {
		uint256 asset;
		uint256 UDebt;
	}

	// Array of all active trove addresses - used to to compute an approximate hint off-chain, for the sorted list insertion
	mapping(address => address[]) public TroveOwners;

	// Error trackers for the trove redistribution calculation
	mapping(address => uint256) public lastETHError_Redistribution;
	mapping(address => uint256) public lastUDebtError_Redistribution;

	bool public isInitialized;

	address public redemptionManagerAddress;

	function onlyBorrowerOperationsOrRedemptionManager() private view {
		if (msg.sender != borrowerOperationsAddress && msg.sender != redemptionManagerAddress) {
			revert NoBorrowerOperations();
		}
	}

	modifier troveIsActive(address _asset, address _borrower) {
		require(isTroveActive(_asset, _borrower), "TroveManager: Trove is not active");
		_;
	}

	// --- Dependency setter ---

	function setAddresses(
		address _borrowerOperationsAddress,
		address _stabilityPoolManagerAddress,
		address _gasPoolAddress,
		address _collSurplusPoolAddress,
		address _uTokenAddress,
		address _sortedTrovesAddress,
		address _youStakingAddress,
		address _vestaParamsAddress
	) external override initializer {
		require(!isInitialized, "!initialized");

		checkContract(_borrowerOperationsAddress);
		checkContract(_stabilityPoolManagerAddress);
		checkContract(_gasPoolAddress);
		checkContract(_collSurplusPoolAddress);
		checkContract(_uTokenAddress);
		checkContract(_sortedTrovesAddress);
		checkContract(_youStakingAddress);
		checkContract(_vestaParamsAddress);
		isInitialized = true;

		__Ownable_init();

		borrowerOperationsAddress = _borrowerOperationsAddress;
		stabilityPoolManager = IStabilityPoolManager(_stabilityPoolManagerAddress);
		gasPoolAddress = _gasPoolAddress;
		collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
		uToken = IUToken(_uTokenAddress);
		sortedTroves = ISortedTroves(_sortedTrovesAddress);
		youStaking = IYOUStaking(_youStakingAddress);

		setVestaParameters(_vestaParamsAddress);

		emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
		emit StabilityPoolAddressChanged(_stabilityPoolManagerAddress);
		emit GasPoolAddressChanged(_gasPoolAddress);
		emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
		emit UTokenAddressChanged(_uTokenAddress);
		emit SortedTrovesAddressChanged(_sortedTrovesAddress);
		emit YOUStakingAddressChanged(_youStakingAddress);
	}

	function setRedemptionManager(address _redemptionManagerAddress) external onlyOwner {
		checkContract(_redemptionManagerAddress);
		redemptionManagerAddress = _redemptionManagerAddress;
	}

	// --- Getters ---
	function getTrove(address _borrower, address _asset) external view returns (Trove memory) {
		_isWstETH(_asset);
		return Troves[_borrower][_asset];
	}

	function setTrove(address _borrower, address _asset, Trove memory _trove) external {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();

		Troves[_borrower][_asset] = _trove;
	}

	function getTroveOwnersCount(address _asset) external view override returns (uint256) {
		_isWstETH(_asset);
		return TroveOwners[_asset].length;
	}

	function getTroveFromTroveOwnersArray(
		address _asset,
		uint256 _index
	) external view override returns (address) {
		_isWstETH(_asset);
		return TroveOwners[_asset][_index];
	}

	// --- Trove Liquidation functions ---

	// Single liquidation function. Closes the trove if its ICR is lower than the minimum collateral ratio.
	function liquidate(
		address _asset,
		address _borrower
	) external override troveIsActive(_asset, _borrower) {
		_isWstETH(_asset);
		address[] memory borrowers = new address[](1);
		borrowers[0] = _borrower;
		batchLiquidateTroves(_asset, borrowers);
	}

	// --- Inner single liquidation functions ---

	// Liquidate one trove, in Normal Mode.
	function _liquidateNormalMode(
		address _asset,
		IActivePool _activePool,
		IDefaultPool _defaultPool,
		address _borrower,
		uint256 _UInStabPool
	) internal returns (LiquidationValues memory singleLiquidation) {
		LocalVariables_InnerSingleLiquidateFunction memory vars;

		(
			singleLiquidation.entireTroveDebt,
			singleLiquidation.entireTroveColl,
			vars.pendingDebtReward,
			vars.pendingCollReward
		) = getEntireDebtAndColl(_asset, _borrower);

		_movePendingTroveRewardsToActivePool(
			_asset,
			_activePool,
			_defaultPool,
			vars.pendingDebtReward,
			vars.pendingCollReward
		);
		_removeStake(_asset, _borrower);

		singleLiquidation.collGasCompensation = _getCollGasCompensation(
			_asset,
			singleLiquidation.entireTroveColl
		);
		singleLiquidation.UGasCompensation = vestaParams.U_GAS_COMPENSATION(_asset);
		uint256 collToLiquidate = singleLiquidation.entireTroveColl.sub(
			singleLiquidation.collGasCompensation
		);

		(
			singleLiquidation.debtToOffset,
			singleLiquidation.collToSendToSP,
			singleLiquidation.debtToRedistribute,
			singleLiquidation.collToRedistribute
		) = _getOffsetAndRedistributionVals(
			singleLiquidation.entireTroveDebt,
			collToLiquidate,
			_UInStabPool
		);

		_closeTrove(_asset, _borrower, Status.closedByLiquidation);
		emit TroveLiquidated(
			_asset,
			_borrower,
			singleLiquidation.entireTroveDebt,
			singleLiquidation.entireTroveColl,
			TroveManagerOperation.liquidateInNormalMode
		);
		emit TroveUpdated(_asset, _borrower, 0, 0, 0, TroveManagerOperation.liquidateInNormalMode);
		return singleLiquidation;
	}

	// Liquidate one trove, in Recovery Mode.
	function _liquidateRecoveryMode(
		address _asset,
		IActivePool _activePool,
		IDefaultPool _defaultPool,
		address _borrower,
		uint256 _ICR,
		uint256 _UInStabPool,
		uint256 _TCR,
		uint256 _price
	) internal returns (LiquidationValues memory singleLiquidation) {
		LocalVariables_InnerSingleLiquidateFunction memory vars;
		if (TroveOwners[_asset].length <= 1) {
			return singleLiquidation;
		} // don't liquidate if last trove
		(
			singleLiquidation.entireTroveDebt,
			singleLiquidation.entireTroveColl,
			vars.pendingDebtReward,
			vars.pendingCollReward
		) = getEntireDebtAndColl(_asset, _borrower);

		singleLiquidation.collGasCompensation = _getCollGasCompensation(
			_asset,
			singleLiquidation.entireTroveColl
		);
		singleLiquidation.UGasCompensation = vestaParams.U_GAS_COMPENSATION(_asset);
		vars.collToLiquidate = singleLiquidation.entireTroveColl.sub(
			singleLiquidation.collGasCompensation
		);

		// If ICR <= 100%, purely redistribute the Trove across all active Troves
		if (_ICR <= vestaParams._100pct()) {
			_movePendingTroveRewardsToActivePool(
				_asset,
				_activePool,
				_defaultPool,
				vars.pendingDebtReward,
				vars.pendingCollReward
			);
			_removeStake(_asset, _borrower);

			singleLiquidation.debtToOffset = 0;
			singleLiquidation.collToSendToSP = 0;
			singleLiquidation.debtToRedistribute = singleLiquidation.entireTroveDebt;
			singleLiquidation.collToRedistribute = vars.collToLiquidate;

			_closeTrove(_asset, _borrower, Status.closedByLiquidation);
			emit TroveLiquidated(
				_asset,
				_borrower,
				singleLiquidation.entireTroveDebt,
				singleLiquidation.entireTroveColl,
				TroveManagerOperation.liquidateInRecoveryMode
			);
			emit TroveUpdated(
				_asset,
				_borrower,
				0,
				0,
				0,
				TroveManagerOperation.liquidateInRecoveryMode
			);

			// If 100% < ICR < MCR, offset as much as possible, and redistribute the remainder
		} else if ((_ICR > vestaParams._100pct()) && (_ICR < vestaParams.MCR(_asset))) {
			_movePendingTroveRewardsToActivePool(
				_asset,
				_activePool,
				_defaultPool,
				vars.pendingDebtReward,
				vars.pendingCollReward
			);
			_removeStake(_asset, _borrower);

			(
				singleLiquidation.debtToOffset,
				singleLiquidation.collToSendToSP,
				singleLiquidation.debtToRedistribute,
				singleLiquidation.collToRedistribute
			) = _getOffsetAndRedistributionVals(
				singleLiquidation.entireTroveDebt,
				vars.collToLiquidate,
				_UInStabPool
			);

			_closeTrove(_asset, _borrower, Status.closedByLiquidation);
			emit TroveLiquidated(
				_asset,
				_borrower,
				singleLiquidation.entireTroveDebt,
				singleLiquidation.entireTroveColl,
				TroveManagerOperation.liquidateInRecoveryMode
			);
			emit TroveUpdated(
				_asset,
				_borrower,
				0,
				0,
				0,
				TroveManagerOperation.liquidateInRecoveryMode
			);
			/*
			 * If 110% <= ICR < current TCR (accounting for the preceding liquidations in the current sequence)
			 * and there is U in the Stability Pool, only offset, with no redistribution,
			 * but at a capped rate of 1.1 and only if the whole debt can be liquidated.
			 * The remainder due to the capped rate will be claimable as collateral surplus.
			 */
		} else if (
			(_ICR >= vestaParams.MCR(_asset)) &&
			(_ICR < _TCR) &&
			(singleLiquidation.entireTroveDebt <= _UInStabPool)
		) {
			_movePendingTroveRewardsToActivePool(
				_asset,
				_activePool,
				_defaultPool,
				vars.pendingDebtReward,
				vars.pendingCollReward
			);
			assert(_UInStabPool != 0);

			_removeStake(_asset, _borrower);
			singleLiquidation = _getCappedOffsetVals(
				_asset,
				singleLiquidation.entireTroveDebt,
				singleLiquidation.entireTroveColl,
				_price
			);

			_closeTrove(_asset, _borrower, Status.closedByLiquidation);
			if (singleLiquidation.collSurplus > 0) {
				collSurplusPool.accountSurplus(_asset, _borrower, singleLiquidation.collSurplus);
			}

			emit TroveLiquidated(
				_asset,
				_borrower,
				singleLiquidation.entireTroveDebt,
				singleLiquidation.collToSendToSP,
				TroveManagerOperation.liquidateInRecoveryMode
			);
			emit TroveUpdated(
				_asset,
				_borrower,
				0,
				0,
				0,
				TroveManagerOperation.liquidateInRecoveryMode
			);
		} else {
			// if (_ICR >= MCR && ( _ICR >= _TCR || singleLiquidation.entireTroveDebt > _UInStabPool))
			LiquidationValues memory zeroVals;
			return zeroVals;
		}

		return singleLiquidation;
	}

	/* In a full liquidation, returns the values for a trove's coll and debt to be offset, and coll and debt to be
	 * redistributed to active troves.
	 */
	function _getOffsetAndRedistributionVals(
		uint256 _debt,
		uint256 _coll,
		uint256 _UInStabPool
	)
		internal
		pure
		returns (
			uint256 debtToOffset,
			uint256 collToSendToSP,
			uint256 debtToRedistribute,
			uint256 collToRedistribute
		)
	{
		if (_UInStabPool > 0) {
			/*
			 * Offset as much debt & collateral as possible against the Stability Pool, and redistribute the remainder
			 * between all active troves.
			 *
			 *  If the trove's debt is larger than the deposited U in the Stability Pool:
			 *
			 *  - Offset an amount of the trove's debt equal to the U in the Stability Pool
			 *  - Send a fraction of the trove's collateral to the Stability Pool, equal to the fraction of its offset debt
			 *
			 */
			debtToOffset = VestaMath._min(_debt, _UInStabPool);
			collToSendToSP = _coll.mul(debtToOffset).div(_debt);
			debtToRedistribute = _debt.sub(debtToOffset);
			collToRedistribute = _coll.sub(collToSendToSP);
		} else {
			debtToOffset = 0;
			collToSendToSP = 0;
			debtToRedistribute = _debt;
			collToRedistribute = _coll;
		}
	}

	/*
	 *  Get its offset coll/debt and ETH gas comp, and close the trove.
	 */
	function _getCappedOffsetVals(
		address _asset,
		uint256 _entireTroveDebt,
		uint256 _entireTroveColl,
		uint256 _price
	) internal view returns (LiquidationValues memory singleLiquidation) {
		singleLiquidation.entireTroveDebt = _entireTroveDebt;
		singleLiquidation.entireTroveColl = _entireTroveColl;
		uint256 cappedCollPortion = _entireTroveDebt.mul(vestaParams.MCR(_asset)).div(_price);

		singleLiquidation.collGasCompensation = _getCollGasCompensation(_asset, cappedCollPortion);
		singleLiquidation.UGasCompensation = vestaParams.U_GAS_COMPENSATION(_asset);

		singleLiquidation.debtToOffset = _entireTroveDebt;
		singleLiquidation.collToSendToSP = cappedCollPortion.sub(
			singleLiquidation.collGasCompensation
		);
		singleLiquidation.collSurplus = _entireTroveColl.sub(cappedCollPortion);
		singleLiquidation.debtToRedistribute = 0;
		singleLiquidation.collToRedistribute = 0;
	}

	/*
	 * Liquidate a sequence of troves. Closes a maximum number of n under-collateralized Troves,
	 * starting from the one with the lowest collateral ratio in the system, and moving upwards
	 */
	function liquidateTroves(address _asset, uint256 _n) external override {
		_isWstETH(_asset);
		ContractsCache memory contractsCache = ContractsCache(
			vestaParams.activePool(),
			vestaParams.defaultPool(),
			IUToken(address(0)),
			IYOUStaking(address(0)),
			sortedTroves,
			ICollSurplusPool(address(0)),
			address(0)
		);
		IStabilityPool stabilityPoolCached = stabilityPoolManager.getAssetStabilityPool(_asset);

		LocalVariables_OuterLiquidationFunction memory vars;

		LiquidationTotals memory totals;

		vars.price = vestaParams.priceFeed().fetchPrice(_asset);
		vars.UInStabPool = stabilityPoolCached.getTotalUDeposits();
		vars.recoveryModeAtStart = _checkRecoveryMode(_asset, vars.price);

		// Perform the appropriate liquidation sequence - tally the values, and obtain their totals
		if (vars.recoveryModeAtStart) {
			totals = _getTotalsFromLiquidateTrovesSequence_RecoveryMode(
				_asset,
				contractsCache,
				vars.price,
				vars.UInStabPool,
				_n
			);
		} else {
			// if !vars.recoveryModeAtStart
			totals = _getTotalsFromLiquidateTrovesSequence_NormalMode(
				_asset,
				contractsCache.activePool,
				contractsCache.defaultPool,
				vars.price,
				vars.UInStabPool,
				_n
			);
		}

		require(totals.totalDebtInSequence > 0, "TroveManager: nothing to liquidate");

		// Move liquidated ETH and U to the appropriate pools
		stabilityPoolCached.offset(totals.totalDebtToOffset, totals.totalCollToSendToSP);
		_redistributeDebtAndColl(
			_asset,
			contractsCache.activePool,
			contractsCache.defaultPool,
			totals.totalDebtToRedistribute,
			totals.totalCollToRedistribute
		);
		if (totals.totalCollSurplus > 0) {
			contractsCache.activePool.sendAsset(
				_asset,
				address(collSurplusPool),
				totals.totalCollSurplus
			);
		}

		// Update system snapshots
		_updateSystemSnapshots_excludeCollRemainder(
			_asset,
			contractsCache.activePool,
			totals.totalCollGasCompensation
		);

		vars.liquidatedDebt = totals.totalDebtInSequence;
		vars.liquidatedColl = totals.totalCollInSequence.sub(totals.totalCollGasCompensation).sub(
			totals.totalCollSurplus
		);
		emit Liquidation(
			_asset,
			vars.liquidatedDebt,
			vars.liquidatedColl,
			totals.totalCollGasCompensation,
			totals.totalUGasCompensation
		);

		// Send gas compensation to caller
		_sendGasCompensation(
			_asset,
			contractsCache.activePool,
			msg.sender,
			totals.totalUGasCompensation,
			totals.totalCollGasCompensation
		);
	}

	/*
	 * This function is used when the liquidateTroves sequence starts during Recovery Mode. However, it
	 * handle the case where the system *leaves* Recovery Mode, part way through the liquidation sequence
	 */
	function _getTotalsFromLiquidateTrovesSequence_RecoveryMode(
		address _asset,
		ContractsCache memory _contractsCache,
		uint256 _price,
		uint256 _UInStabPool,
		uint256 _n
	) internal returns (LiquidationTotals memory totals) {
		LocalVariables_AssetBorrowerPrice memory assetVars = LocalVariables_AssetBorrowerPrice(
			_asset,
			address(0),
			_price
		);

		LocalVariables_LiquidationSequence memory vars;
		LiquidationValues memory singleLiquidation;

		vars.remainingUInStabPool = _UInStabPool;
		vars.backToNormalMode = false;
		vars.entireSystemDebt = getEntireSystemDebt(assetVars._asset);
		vars.entireSystemColl = getEntireSystemColl(assetVars._asset);

		vars.user = _contractsCache.sortedTroves.getLast(assetVars._asset);
		address firstUser = _contractsCache.sortedTroves.getFirst(assetVars._asset);
		for (vars.i = 0; vars.i < _n && vars.user != firstUser; vars.i++) {
			// we need to cache it, because current user is likely going to be deleted
			address nextUser = _contractsCache.sortedTroves.getPrev(assetVars._asset, vars.user);

			vars.ICR = getCurrentICR(assetVars._asset, vars.user, assetVars._price);

			if (!vars.backToNormalMode) {
				// Break the loop if ICR is greater than MCR and Stability Pool is empty
				if (vars.ICR >= vestaParams.MCR(_asset) && vars.remainingUInStabPool == 0) {
					break;
				}

				uint256 TCR = VestaMath._computeCR(
					vars.entireSystemColl,
					vars.entireSystemDebt,
					assetVars._price
				);

				singleLiquidation = _liquidateRecoveryMode(
					assetVars._asset,
					_contractsCache.activePool,
					_contractsCache.defaultPool,
					vars.user,
					vars.ICR,
					vars.remainingUInStabPool,
					TCR,
					assetVars._price
				);

				// Update aggregate trackers
				vars.remainingUInStabPool = vars.remainingUInStabPool.sub(
					singleLiquidation.debtToOffset
				);
				vars.entireSystemDebt = vars.entireSystemDebt.sub(singleLiquidation.debtToOffset);
				vars.entireSystemColl = vars
					.entireSystemColl
					.sub(singleLiquidation.collToSendToSP)
					.sub(singleLiquidation.collGasCompensation)
					.sub(singleLiquidation.collSurplus);

				// Add liquidation values to their respective running totals
				totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

				vars.backToNormalMode = !_checkPotentialRecoveryMode(
					_asset,
					vars.entireSystemColl,
					vars.entireSystemDebt,
					assetVars._price
				);
			} else if (vars.backToNormalMode && vars.ICR < vestaParams.MCR(_asset)) {
				singleLiquidation = _liquidateNormalMode(
					assetVars._asset,
					_contractsCache.activePool,
					_contractsCache.defaultPool,
					vars.user,
					vars.remainingUInStabPool
				);

				vars.remainingUInStabPool = vars.remainingUInStabPool.sub(
					singleLiquidation.debtToOffset
				);

				// Add liquidation values to their respective running totals
				totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
			} else break; // break if the loop reaches a Trove with ICR >= MCR

			vars.user = nextUser;
		}
	}

	function _getTotalsFromLiquidateTrovesSequence_NormalMode(
		address _asset,
		IActivePool _activePool,
		IDefaultPool _defaultPool,
		uint256 _price,
		uint256 _UInStabPool,
		uint256 _n
	) internal returns (LiquidationTotals memory totals) {
		LocalVariables_LiquidationSequence memory vars;
		LiquidationValues memory singleLiquidation;
		ISortedTroves sortedTrovesCached = sortedTroves;

		vars.remainingUInStabPool = _UInStabPool;

		for (vars.i = 0; vars.i < _n; vars.i++) {
			vars.user = sortedTrovesCached.getLast(_asset);
			vars.ICR = getCurrentICR(_asset, vars.user, _price);

			if (vars.ICR < vestaParams.MCR(_asset)) {
				singleLiquidation = _liquidateNormalMode(
					_asset,
					_activePool,
					_defaultPool,
					vars.user,
					vars.remainingUInStabPool
				);

				vars.remainingUInStabPool = vars.remainingUInStabPool.sub(
					singleLiquidation.debtToOffset
				);

				// Add liquidation values to their respective running totals
				totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
			} else break; // break if the loop reaches a Trove with ICR >= MCR
		}
	}

	/*
	 * Attempt to liquidate a custom list of troves provided by the caller.
	 */
	function batchLiquidateTroves(address _asset, address[] memory _troveArray) public override {
		require(_troveArray.length != 0, "TroveManager: address array is empty");
		_isWstETH(_asset);

		IActivePool activePoolCached = vestaParams.activePool();
		IDefaultPool defaultPoolCached = vestaParams.defaultPool();
		IStabilityPool stabilityPoolCached = stabilityPoolManager.getAssetStabilityPool(_asset);

		LocalVariables_OuterLiquidationFunction memory vars;
		LiquidationTotals memory totals;

		vars.UInStabPool = stabilityPoolCached.getTotalUDeposits();
		vars.price = vestaParams.priceFeed().fetchPrice(_asset);

		vars.recoveryModeAtStart = _checkRecoveryMode(_asset, vars.price);

		// Perform the appropriate liquidation sequence - tally values and obtain their totals.
		if (vars.recoveryModeAtStart) {
			totals = _getTotalFromBatchLiquidate_RecoveryMode(
				_asset,
				activePoolCached,
				defaultPoolCached,
				vars.price,
				vars.UInStabPool,
				_troveArray
			);
		} else {
			//  if !vars.recoveryModeAtStart
			totals = _getTotalsFromBatchLiquidate_NormalMode(
				_asset,
				activePoolCached,
				defaultPoolCached,
				vars.price,
				vars.UInStabPool,
				_troveArray
			);
		}

		require(totals.totalDebtInSequence > 0, "TroveManager: nothing to liquidate");

		// Move liquidated ETH and U to the appropriate pools
		stabilityPoolCached.offset(totals.totalDebtToOffset, totals.totalCollToSendToSP);
		_redistributeDebtAndColl(
			_asset,
			activePoolCached,
			defaultPoolCached,
			totals.totalDebtToRedistribute,
			totals.totalCollToRedistribute
		);
		if (totals.totalCollSurplus > 0) {
			activePoolCached.sendAsset(_asset, address(collSurplusPool), totals.totalCollSurplus);
		}

		// Update system snapshots
		_updateSystemSnapshots_excludeCollRemainder(
			_asset,
			activePoolCached,
			totals.totalCollGasCompensation
		);

		vars.liquidatedDebt = totals.totalDebtInSequence;
		vars.liquidatedColl = totals.totalCollInSequence.sub(totals.totalCollGasCompensation).sub(
			totals.totalCollSurplus
		);
		emit Liquidation(
			_asset,
			vars.liquidatedDebt,
			vars.liquidatedColl,
			totals.totalCollGasCompensation,
			totals.totalUGasCompensation
		);

		// Send gas compensation to caller
		_sendGasCompensation(
			_asset,
			activePoolCached,
			msg.sender,
			totals.totalUGasCompensation,
			totals.totalCollGasCompensation
		);
	}

	/*
	 * This function is used when the batch liquidation sequence starts during Recovery Mode. However, it
	 * handle the case where the system *leaves* Recovery Mode, part way through the liquidation sequence
	 */
	function _getTotalFromBatchLiquidate_RecoveryMode(
		address _asset,
		IActivePool _activePool,
		IDefaultPool _defaultPool,
		uint256 _price,
		uint256 _UInStabPool,
		address[] memory _troveArray
	) internal returns (LiquidationTotals memory totals) {
		LocalVariables_LiquidationSequence memory vars;
		LiquidationValues memory singleLiquidation;

		vars.remainingUInStabPool = _UInStabPool;
		vars.backToNormalMode = false;
		vars.entireSystemDebt = getEntireSystemDebt(_asset);
		vars.entireSystemColl = getEntireSystemColl(_asset);

		for (vars.i = 0; vars.i < _troveArray.length; vars.i++) {
			vars.user = _troveArray[vars.i];
			// Skip non-active troves
			if (Troves[vars.user][_asset].status != Status.active) {
				continue;
			}

			vars.ICR = getCurrentICR(_asset, vars.user, _price);

			if (!vars.backToNormalMode) {
				// Skip this trove if ICR is greater than MCR and Stability Pool is empty
				if (vars.ICR >= vestaParams.MCR(_asset) && vars.remainingUInStabPool == 0) {
					continue;
				}

				uint256 TCR = VestaMath._computeCR(
					vars.entireSystemColl,
					vars.entireSystemDebt,
					_price
				);

				singleLiquidation = _liquidateRecoveryMode(
					_asset,
					_activePool,
					_defaultPool,
					vars.user,
					vars.ICR,
					vars.remainingUInStabPool,
					TCR,
					_price
				);

				// Update aggregate trackers
				vars.remainingUInStabPool = vars.remainingUInStabPool.sub(
					singleLiquidation.debtToOffset
				);
				vars.entireSystemDebt = vars.entireSystemDebt.sub(singleLiquidation.debtToOffset);
				vars.entireSystemColl = vars
					.entireSystemColl
					.sub(singleLiquidation.collToSendToSP)
					.sub(singleLiquidation.collGasCompensation)
					.sub(singleLiquidation.collSurplus);

				// Add liquidation values to their respective running totals
				totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

				vars.backToNormalMode = !_checkPotentialRecoveryMode(
					_asset,
					vars.entireSystemColl,
					vars.entireSystemDebt,
					_price
				);
			} else if (vars.backToNormalMode && vars.ICR < vestaParams.MCR(_asset)) {
				singleLiquidation = _liquidateNormalMode(
					_asset,
					_activePool,
					_defaultPool,
					vars.user,
					vars.remainingUInStabPool
				);
				vars.remainingUInStabPool = vars.remainingUInStabPool.sub(
					singleLiquidation.debtToOffset
				);

				// Add liquidation values to their respective running totals
				totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
			} else continue; // In Normal Mode skip troves with ICR >= MCR
		}
	}

	function _getTotalsFromBatchLiquidate_NormalMode(
		address _asset,
		IActivePool _activePool,
		IDefaultPool _defaultPool,
		uint256 _price,
		uint256 _UInStabPool,
		address[] memory _troveArray
	) internal returns (LiquidationTotals memory totals) {
		LocalVariables_LiquidationSequence memory vars;
		LiquidationValues memory singleLiquidation;

		vars.remainingUInStabPool = _UInStabPool;

		for (vars.i = 0; vars.i < _troveArray.length; vars.i++) {
			vars.user = _troveArray[vars.i];
			vars.ICR = getCurrentICR(_asset, vars.user, _price);

			if (vars.ICR < vestaParams.MCR(_asset)) {
				singleLiquidation = _liquidateNormalMode(
					_asset,
					_activePool,
					_defaultPool,
					vars.user,
					vars.remainingUInStabPool
				);
				vars.remainingUInStabPool = vars.remainingUInStabPool.sub(
					singleLiquidation.debtToOffset
				);

				// Add liquidation values to their respective running totals
				totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
			}
		}
	}

	// --- Liquidation helper functions ---

	function _addLiquidationValuesToTotals(
		LiquidationTotals memory oldTotals,
		LiquidationValues memory singleLiquidation
	) internal pure returns (LiquidationTotals memory newTotals) {
		// Tally all the values with their respective running totals
		newTotals.totalCollGasCompensation = oldTotals.totalCollGasCompensation.add(
			singleLiquidation.collGasCompensation
		);
		newTotals.totalUGasCompensation = oldTotals.totalUGasCompensation.add(
			singleLiquidation.UGasCompensation
		);
		newTotals.totalDebtInSequence = oldTotals.totalDebtInSequence.add(
			singleLiquidation.entireTroveDebt
		);
		newTotals.totalCollInSequence = oldTotals.totalCollInSequence.add(
			singleLiquidation.entireTroveColl
		);
		newTotals.totalDebtToOffset = oldTotals.totalDebtToOffset.add(
			singleLiquidation.debtToOffset
		);
		newTotals.totalCollToSendToSP = oldTotals.totalCollToSendToSP.add(
			singleLiquidation.collToSendToSP
		);
		newTotals.totalDebtToRedistribute = oldTotals.totalDebtToRedistribute.add(
			singleLiquidation.debtToRedistribute
		);
		newTotals.totalCollToRedistribute = oldTotals.totalCollToRedistribute.add(
			singleLiquidation.collToRedistribute
		);
		newTotals.totalCollSurplus = oldTotals.totalCollSurplus.add(singleLiquidation.collSurplus);

		return newTotals;
	}

	function _sendGasCompensation(
		address _asset,
		IActivePool _activePool,
		address _liquidator,
		uint256 _U,
		uint256 _ETH
	) internal {
		if (_U > 0) {
			uToken.returnFromPool(gasPoolAddress, _liquidator, _U);
		}

		if (_ETH > 0) {
			_activePool.sendAsset(_asset, _liquidator, _ETH);
		}
	}

	// Move a Trove's pending debt and collateral rewards from distributions, from the Default Pool to the Active Pool
	function _movePendingTroveRewardsToActivePool(
		address _asset,
		IActivePool _activePool,
		IDefaultPool _defaultPool,
		uint256 _U,
		uint256 _amount
	) internal {
		_defaultPool.decreaseUDebt(_asset, _U);
		_activePool.increaseUDebt(_asset, _U);
		_defaultPool.sendAssetToActivePool(_asset, _amount);
	}

	// --- Helper functions ---

	// Return the nominal collateral ratio (ICR) of a given Trove, without the price. Takes a trove's pending coll and debt rewards from redistributions into account.
	function getNominalICR(
		address _asset,
		address _borrower
	) public view override returns (uint256) {
		_isWstETH(_asset);
		(uint256 currentAsset, uint256 currentUDebt) = _getCurrentTroveAmounts(_asset, _borrower);

		uint256 NICR = VestaMath._computeNominalCR(currentAsset, currentUDebt);
		return NICR;
	}

	// Return the current collateral ratio (ICR) of a given Trove. Takes a trove's pending coll and debt rewards from redistributions into account.
	function getCurrentICR(
		address _asset,
		address _borrower,
		uint256 _price
	) public view override returns (uint256) {
		_isWstETH(_asset);
		(uint256 currentAsset, uint256 currentUDebt) = _getCurrentTroveAmounts(_asset, _borrower);

		uint256 ICR = VestaMath._computeCR(currentAsset, currentUDebt, _price);
		return ICR;
	}

	function _getCurrentTroveAmounts(
		address _asset,
		address _borrower
	) internal view returns (uint256, uint256) {
		uint256 pendingAssetReward = getPendingAssetReward(_asset, _borrower);
		uint256 pendingUDebtReward = getPendingUDebtReward(_asset, _borrower);

		uint256 currentAsset = Troves[_borrower][_asset].coll.add(pendingAssetReward);
		uint256 currentUDebt = Troves[_borrower][_asset].debt.add(pendingUDebtReward);

		return (currentAsset, currentUDebt);
	}

	function applyPendingRewards(address _asset, address _borrower) external override {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		return
			_applyPendingRewards(
				_asset,
				vestaParams.activePool(),
				vestaParams.defaultPool(),
				_borrower
			);
	}

	function applyPendingRewardsForRedemption(
		address _asset,
		IActivePool _activePool,
		IDefaultPool _defaultPool,
		address _borrower
	) external {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		return _applyPendingRewards(_asset, _activePool, _defaultPool, _borrower);
	}

	// Add the borrowers's coll and debt rewards earned from redistributions, to their Trove
	function _applyPendingRewards(
		address _asset,
		IActivePool _activePool,
		IDefaultPool _defaultPool,
		address _borrower
	) internal {
		if (!hasPendingRewards(_asset, _borrower)) {
			return;
		}

		assert(isTroveActive(_asset, _borrower));

		// Compute pending rewards
		uint256 pendingAssetReward = getPendingAssetReward(_asset, _borrower);
		uint256 pendingUDebtReward = getPendingUDebtReward(_asset, _borrower);

		// Apply pending rewards to trove's state
		Troves[_borrower][_asset].coll = Troves[_borrower][_asset].coll.add(pendingAssetReward);
		Troves[_borrower][_asset].debt = Troves[_borrower][_asset].debt.add(pendingUDebtReward);

		_updateTroveRewardSnapshots(_asset, _borrower);

		// Transfer from DefaultPool to ActivePool
		_movePendingTroveRewardsToActivePool(
			_asset,
			_activePool,
			_defaultPool,
			pendingUDebtReward,
			pendingAssetReward
		);

		emit TroveUpdated(
			_asset,
			_borrower,
			Troves[_borrower][_asset].debt,
			Troves[_borrower][_asset].coll,
			Troves[_borrower][_asset].stake,
			TroveManagerOperation.applyPendingRewards
		);
	}

	// Update borrower's snapshots of L_ETH and L_UDebt to reflect the current values
	function updateTroveRewardSnapshots(address _asset, address _borrower) external override {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		return _updateTroveRewardSnapshots(_asset, _borrower);
	}

	function _updateTroveRewardSnapshots(address _asset, address _borrower) internal {
		rewardSnapshots[_borrower][_asset].asset = L_ASSETS[_asset];
		rewardSnapshots[_borrower][_asset].UDebt = L_UDebts[_asset];
		emit TroveSnapshotsUpdated(_asset, L_ASSETS[_asset], L_UDebts[_asset]);
	}

	// Get the borrower's pending accumulated ETH reward, earned by their stake
	function getPendingAssetReward(
		address _asset,
		address _borrower
	) public view override returns (uint256) {
		_isWstETH(_asset);
		uint256 snapshotAsset = rewardSnapshots[_borrower][_asset].asset;
		uint256 rewardPerUnitStaked = L_ASSETS[_asset].sub(snapshotAsset);

		if (rewardPerUnitStaked == 0 || !isTroveActive(_asset, _borrower)) {
			return 0;
		}

		uint256 stake = Troves[_borrower][_asset].stake;

		uint256 pendingAssetReward = stake.mul(rewardPerUnitStaked).div(DECIMAL_PRECISION);

		return pendingAssetReward;
	}

	// Get the borrower's pending accumulated U reward, earned by their stake
	function getPendingUDebtReward(
		address _asset,
		address _borrower
	) public view override returns (uint256) {
		_isWstETH(_asset);
		uint256 snapshotUDebt = rewardSnapshots[_borrower][_asset].UDebt;
		uint256 rewardPerUnitStaked = L_UDebts[_asset].sub(snapshotUDebt);

		if (rewardPerUnitStaked == 0 || !isTroveActive(_asset, _borrower)) {
			return 0;
		}

		uint256 stake = Troves[_borrower][_asset].stake;

		uint256 pendingUDebtReward = stake.mul(rewardPerUnitStaked).div(DECIMAL_PRECISION);

		return pendingUDebtReward;
	}

	function hasPendingRewards(
		address _asset,
		address _borrower
	) public view override returns (bool) {
		_isWstETH(_asset);
		if (!isTroveActive(_asset, _borrower)) {
			return false;
		}

		return (rewardSnapshots[_borrower][_asset].asset < L_ASSETS[_asset]);
	}

	function getEntireDebtAndColl(
		address _asset,
		address _borrower
	)
		public
		view
		override
		returns (
			uint256 debt,
			uint256 coll,
			uint256 pendingUDebtReward,
			uint256 pendingAssetReward
		)
	{
		_isWstETH(_asset);
		debt = Troves[_borrower][_asset].debt;
		coll = Troves[_borrower][_asset].coll;

		pendingUDebtReward = getPendingUDebtReward(_asset, _borrower);
		pendingAssetReward = getPendingAssetReward(_asset, _borrower);

		debt = debt.add(pendingUDebtReward);
		coll = coll.add(pendingAssetReward);
	}

	function removeStake(address _asset, address _borrower) external override {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		return _removeStake(_asset, _borrower);
	}

	function _removeStake(address _asset, address _borrower) internal {
		uint256 stake = Troves[_borrower][_asset].stake;
		totalStakes[_asset] = totalStakes[_asset].sub(stake);
		Troves[_borrower][_asset].stake = 0;
	}

	function updateStakeAndTotalStakes(
		address _asset,
		address _borrower
	) external override returns (uint256) {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		return _updateStakeAndTotalStakes(_asset, _borrower);
	}

	// Update borrower's stake based on their latest collateral value
	function _updateStakeAndTotalStakes(
		address _asset,
		address _borrower
	) internal returns (uint256) {
		uint256 newStake = _computeNewStake(_asset, Troves[_borrower][_asset].coll);
		uint256 oldStake = Troves[_borrower][_asset].stake;
		Troves[_borrower][_asset].stake = newStake;

		totalStakes[_asset] = totalStakes[_asset].sub(oldStake).add(newStake);
		emit TotalStakesUpdated(_asset, totalStakes[_asset]);

		return newStake;
	}

	// Calculate a new stake based on the snapshots of the totalStakes and totalCollateral taken at the last liquidation
	function _computeNewStake(address _asset, uint256 _coll) internal view returns (uint256) {
		uint256 stake;
		if (totalCollateralSnapshot[_asset] == 0) {
			stake = _coll;
		} else {
			/*
			 * The following assert() holds true because:
			 * - The system always contains >= 1 trove
			 * - When we close or liquidate a trove, we redistribute the pending rewards, so if all troves were closed/liquidated,
			 * rewards would’ve been emptied and totalCollateralSnapshot would be zero too.
			 */
			assert(totalStakesSnapshot[_asset] > 0);
			stake = _coll.mul(totalStakesSnapshot[_asset]).div(totalCollateralSnapshot[_asset]);
		}
		return stake;
	}

	function _redistributeDebtAndColl(
		address _asset,
		IActivePool _activePool,
		IDefaultPool _defaultPool,
		uint256 _debt,
		uint256 _coll
	) internal {
		if (_debt == 0) {
			return;
		}

		/*
		 * Add distributed coll and debt rewards-per-unit-staked to the running totals. Division uses a "feedback"
		 * error correction, to keep the cumulative error low in the running totals L_ETH and L_UDebt:
		 *
		 * 1) Form numerators which compensate for the floor division errors that occurred the last time this
		 * function was called.
		 * 2) Calculate "per-unit-staked" ratios.
		 * 3) Multiply each ratio back by its denominator, to reveal the current floor division error.
		 * 4) Store these errors for use in the next correction when this function is called.
		 * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
		 */
		uint256 ETHNumerator = _coll.mul(DECIMAL_PRECISION).add(
			lastETHError_Redistribution[_asset]
		);
		uint256 UDebtNumerator = _debt.mul(DECIMAL_PRECISION).add(
			lastUDebtError_Redistribution[_asset]
		);

		// Get the per-unit-staked terms
		uint256 ETHRewardPerUnitStaked = ETHNumerator.div(totalStakes[_asset]);
		uint256 UDebtRewardPerUnitStaked = UDebtNumerator.div(totalStakes[_asset]);

		lastETHError_Redistribution[_asset] = ETHNumerator.sub(
			ETHRewardPerUnitStaked.mul(totalStakes[_asset])
		);
		lastUDebtError_Redistribution[_asset] = UDebtNumerator.sub(
			UDebtRewardPerUnitStaked.mul(totalStakes[_asset])
		);

		// Add per-unit-staked terms to the running totals
		L_ASSETS[_asset] = L_ASSETS[_asset].add(ETHRewardPerUnitStaked);
		L_UDebts[_asset] = L_UDebts[_asset].add(UDebtRewardPerUnitStaked);

		emit LTermsUpdated(_asset, L_ASSETS[_asset], L_UDebts[_asset]);

		_activePool.decreaseUDebt(_asset, _debt);
		_defaultPool.increaseUDebt(_asset, _debt);
		_activePool.sendAsset(_asset, address(_defaultPool), _coll);
	}

	function closeTrove(address _asset, address _borrower) external override {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		return _closeTrove(_asset, _borrower, Status.closedByOwner);
	}

	function closeTroveByRedemption(address _asset, address _borrower) external {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		return _closeTrove(_asset, _borrower, Status.closedByRedemption);
	}

	function _closeTrove(address _asset, address _borrower, Status closedStatus) internal {
		assert(closedStatus != Status.nonExistent && closedStatus != Status.active);

		uint256 TroveOwnersArrayLength = TroveOwners[_asset].length;
		_requireMoreThanOneTroveInSystem(_asset, TroveOwnersArrayLength);

		Troves[_borrower][_asset].status = closedStatus;
		Troves[_borrower][_asset].coll = 0;
		Troves[_borrower][_asset].debt = 0;

		rewardSnapshots[_borrower][_asset].asset = 0;
		rewardSnapshots[_borrower][_asset].UDebt = 0;

		_removeTroveOwner(_asset, _borrower, TroveOwnersArrayLength);
		sortedTroves.remove(_asset, _borrower);
	}

	function _updateSystemSnapshots_excludeCollRemainder(
		address _asset,
		IActivePool _activePool,
		uint256 _collRemainder
	) internal {
		totalStakesSnapshot[_asset] = totalStakes[_asset];

		uint256 activeColl = _activePool.getAssetBalance(_asset);
		uint256 liquidatedColl = vestaParams.defaultPool().getAssetBalance(_asset);
		totalCollateralSnapshot[_asset] = activeColl.sub(_collRemainder).add(liquidatedColl);

		emit SystemSnapshotsUpdated(
			_asset,
			totalStakesSnapshot[_asset],
			totalCollateralSnapshot[_asset]
		);
	}

	function addTroveOwnerToArray(
		address _asset,
		address _borrower
	) external override returns (uint256 index) {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		return _addTroveOwnerToArray(_asset, _borrower);
	}

	function _addTroveOwnerToArray(
		address _asset,
		address _borrower
	) internal returns (uint128 index) {
		TroveOwners[_asset].push(_borrower);

		index = uint128(TroveOwners[_asset].length.sub(1));
		Troves[_borrower][_asset].arrayIndex = index;

		return index;
	}

	function _removeTroveOwner(
		address _asset,
		address _borrower,
		uint256 TroveOwnersArrayLength
	) internal {
		Status troveStatus = Troves[_borrower][_asset].status;
		assert(troveStatus != Status.nonExistent && troveStatus != Status.active);

		uint128 index = Troves[_borrower][_asset].arrayIndex;
		uint256 length = TroveOwnersArrayLength;
		uint256 idxLast = length.sub(1);

		assert(index <= idxLast);

		address addressToMove = TroveOwners[_asset][idxLast];

		TroveOwners[_asset][index] = addressToMove;
		Troves[addressToMove][_asset].arrayIndex = index;
		emit TroveIndexUpdated(_asset, addressToMove, index);

		TroveOwners[_asset].pop();
	}

	function getTCR(address _asset, uint256 _price) external view override returns (uint256) {
		_isWstETH(_asset);
		return _getTCR(_asset, _price);
	}

	function checkRecoveryMode(
		address _asset,
		uint256 _price
	) external view override returns (bool) {
		_isWstETH(_asset);
		return _checkRecoveryMode(_asset, _price);
	}

	function _checkPotentialRecoveryMode(
		address _asset,
		uint256 _entireSystemColl,
		uint256 _entireSystemDebt,
		uint256 _price
	) internal view returns (bool) {
		uint256 TCR = VestaMath._computeCR(_entireSystemColl, _entireSystemDebt, _price);

		return TCR < vestaParams.CCR(_asset);
	}

	function getBorrowingRate(address _asset) public view override returns (uint256) {
		_isWstETH(_asset);
		return _calcBorrowingRate(_asset, baseRate[_asset]);
	}

	function getBorrowingRateWithDecay(address _asset) public view override returns (uint256) {
		_isWstETH(_asset);
		return _calcBorrowingRate(_asset, _calcDecayedBaseRate(_asset));
	}

	function _calcBorrowingRate(
		address _asset,
		uint256 _baseRate
	) internal view returns (uint256) {
		return
			VestaMath._min(
				vestaParams.BORROWING_FEE_FLOOR(_asset).add(_baseRate),
				vestaParams.MAX_BORROWING_FEE(_asset)
			);
	}

	function getBorrowingFee(
		address _asset,
		uint256 _UDebt
	) external view override returns (uint256) {
		_isWstETH(_asset);
		return _calcBorrowingFee(getBorrowingRate(_asset), _UDebt);
	}

	function getBorrowingFeeWithDecay(
		address _asset,
		uint256 _UDebt
	) external view override returns (uint256) {
		_isWstETH(_asset);
		return _calcBorrowingFee(getBorrowingRateWithDecay(_asset), _UDebt);
	}

	function _calcBorrowingFee(
		uint256 _borrowingRate,
		uint256 _UDebt
	) internal pure returns (uint256) {
		return _borrowingRate.mul(_UDebt).div(DECIMAL_PRECISION);
	}

	function decayBaseRateFromBorrowing(address _asset) external override {
		onlyBorrowerOperationsOrRedemptionManager();
		_isWstETH(_asset);
		uint256 decayedBaseRate = _calcDecayedBaseRate(_asset);
		assert(decayedBaseRate <= DECIMAL_PRECISION);

		updateBaseRateAndLastFeeOpTime(_asset, decayedBaseRate);
	}

	function updateBaseRateAndLastFeeOpTime(address _asset, uint256 _rate) public {
		onlyBorrowerOperationsOrRedemptionManager();
		_isWstETH(_asset);

		baseRate[_asset] = _rate;
		emit BaseRateUpdated(_asset, _rate);

		_updateLastFeeOpTime(_asset);
	}

	// Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
	function _updateLastFeeOpTime(address _asset) internal {
		uint256 timePassed = block.timestamp.sub(lastFeeOperationTime[_asset]);

		if (timePassed >= SECONDS_IN_ONE_MINUTE) {
			lastFeeOperationTime[_asset] = block.timestamp;
			emit LastFeeOpTimeUpdated(_asset, block.timestamp);
		}
	}

	function calcDecayedBaseRate(address _asset) external view returns (uint256) {
		onlyBorrowerOperationsOrRedemptionManager();
		_isWstETH(_asset);
		return _calcDecayedBaseRate(_asset);
	}

	function _calcDecayedBaseRate(address _asset) internal view returns (uint256) {
		uint256 minutesPassed = _minutesPassedSinceLastFeeOp(_asset);
		uint256 decayFactor = VestaMath._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

		return baseRate[_asset].mul(decayFactor).div(DECIMAL_PRECISION);
	}

	function _minutesPassedSinceLastFeeOp(address _asset) internal view returns (uint256) {
		return (block.timestamp.sub(lastFeeOperationTime[_asset])).div(SECONDS_IN_ONE_MINUTE);
	}

	function _requireMoreThanOneTroveInSystem(
		address _asset,
		uint256 TroveOwnersArrayLength
	) internal view {
		require(
			TroveOwnersArrayLength > 1 && sortedTroves.getSize(_asset) > 1,
			"TroveManager: Too much trove"
		);
	}

	function isTroveActive(address _asset, address _borrower) internal view returns (bool) {
		return this.getTroveStatus(_asset, _borrower) == uint256(Status.active);
	}

	// --- Trove property getters ---

	function getTroveStatus(
		address _asset,
		address _borrower
	) external view override returns (uint256) {
		_isWstETH(_asset);
		return uint256(Troves[_borrower][_asset].status);
	}

	function getTroveStake(
		address _asset,
		address _borrower
	) external view override returns (uint256) {
		_isWstETH(_asset);
		return Troves[_borrower][_asset].stake;
	}

	function getTroveDebt(
		address _asset,
		address _borrower
	) external view override returns (uint256) {
		_isWstETH(_asset);
		return Troves[_borrower][_asset].debt;
	}

	function getTroveColl(
		address _asset,
		address _borrower
	) external view override returns (uint256) {
		_isWstETH(_asset);
		return Troves[_borrower][_asset].coll;
	}

	// --- Trove property setters, called by BorrowerOperations ---

	function setTroveStatus(address _asset, address _borrower, uint256 _num) external override {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		Troves[_borrower][_asset].asset = _asset;
		Troves[_borrower][_asset].status = Status(_num);
	}

	function increaseTroveColl(
		address _asset,
		address _borrower,
		uint256 _collIncrease
	) external override returns (uint256) {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		uint256 newColl = Troves[_borrower][_asset].coll.add(_collIncrease);
		Troves[_borrower][_asset].coll = newColl;
		return newColl;
	}

	function decreaseTroveColl(
		address _asset,
		address _borrower,
		uint256 _collDecrease
	) external override returns (uint256) {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		uint256 newColl = Troves[_borrower][_asset].coll.sub(_collDecrease);
		Troves[_borrower][_asset].coll = newColl;
		return newColl;
	}

	function increaseTroveDebt(
		address _asset,
		address _borrower,
		uint256 _debtIncrease
	) external override returns (uint256) {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		uint256 newDebt = Troves[_borrower][_asset].debt.add(_debtIncrease);
		Troves[_borrower][_asset].debt = newDebt;
		return newDebt;
	}

	function decreaseTroveDebt(
		address _asset,
		address _borrower,
		uint256 _debtDecrease
	) external override returns (uint256) {
		_isWstETH(_asset);
		onlyBorrowerOperationsOrRedemptionManager();
		uint256 newDebt = Troves[_borrower][_asset].debt.sub(_debtDecrease);
		Troves[_borrower][_asset].debt = newDebt;
		return newDebt;
	}
}

