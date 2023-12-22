// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "./ITroveManager.sol";
import "./PSYBase.sol";
import "./CheckContract.sol";
import "./Initializable.sol";
import "./ITroveManagerHelpers.sol";

contract TroveManager is PSYBase, CheckContract, Initializable, ITroveManager {
	using SafeMath for uint256;
	string public constant NAME = "TroveManager";

	// --- Connected contract declarations ---

	ITroveManagerHelpers public troveManagerHelpers;

	IStabilityPoolManager public stabilityPoolManager;

	address gasPoolAddress;

	ICollSurplusPool collSurplusPool;

	ISLSDToken public override slsdToken;

	IPSYStaking public override psyStaking;

	bool isPSYReady;

	address treasury;

	// A doubly linked list of Troves, sorted by their sorted by their collateral ratios
	ISortedTroves public sortedTroves;

	// --- Data structures ---

	bool public isInitialized;

	mapping(address => bool) public redemptionWhitelist;
	bool public isRedemptionWhitelisted;

	// Internal Function and Modifier onlyBorrowerOperations
	// @dev This workaround was needed in order to reduce bytecode size

	modifier troveIsActive(address _asset, address _borrower) {
		require(troveManagerHelpers.isTroveActive(_asset, _borrower), "IT");
		_;
	}

	// --- Dependency setter ---

	function setAddresses(
		address _stabilityPoolManagerAddress,
		address _gasPoolAddress,
		address _collSurplusPoolAddress,
		address _slsdTokenAddress,
		address _sortedTrovesAddress,
		address _psyStakingAddress,
		address _treasury,
		address _psyParamsAddress,
		address _troveManagerHelpersAddress
	) external override initializer onlyOwner {
		require(!isInitialized, "AI");
		checkContract(_stabilityPoolManagerAddress);
		checkContract(_gasPoolAddress);
		checkContract(_collSurplusPoolAddress);
		checkContract(_slsdTokenAddress);
		checkContract(_sortedTrovesAddress);
		
		checkContract(_psyParamsAddress);
		checkContract(_troveManagerHelpersAddress);
		isInitialized = true;

		stabilityPoolManager = IStabilityPoolManager(_stabilityPoolManagerAddress);
		gasPoolAddress = _gasPoolAddress;
		collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
		slsdToken = ISLSDToken(_slsdTokenAddress);
		sortedTroves = ISortedTroves(_sortedTrovesAddress);
		troveManagerHelpers = ITroveManagerHelpers(_troveManagerHelpersAddress);

		if (_psyStakingAddress != address(0)) {
			checkContract(_psyStakingAddress);
			psyStaking = IPSYStaking(_psyStakingAddress);
			isPSYReady = true;
		} else {
			changeTreasuryAddress(_treasury);
		}
		
		setPSYParameters(_psyParamsAddress);
	}

	// --- Trove Getter functions ---

	function isContractTroveManager() public pure returns (bool) {
		return true;
	}

	// --- Trove Liquidation functions ---

	// Single liquidation function. Closes the trove if its ICR is lower than the minimum collateral ratio.
	function liquidate(address _asset, address _borrower)
		external
		override
		troveIsActive(_asset, _borrower)
	{
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
		uint256 _SLSDInStabPool
	) internal returns (LiquidationValues memory singleLiquidation) {
		LocalVariables_InnerSingleLiquidateFunction memory vars;

		(
			singleLiquidation.entireTroveDebt,
			singleLiquidation.entireTroveColl,
			vars.pendingDebtReward,
			vars.pendingCollReward
		) = troveManagerHelpers.getEntireDebtAndColl(_asset, _borrower);

		troveManagerHelpers.movePendingTroveRewardsToActivePool(
			_asset,
			_activePool,
			_defaultPool,
			vars.pendingDebtReward,
			vars.pendingCollReward
		);
		troveManagerHelpers.removeStake(_asset, _borrower);

		singleLiquidation.collGasCompensation = _getCollGasCompensation(
			_asset,
			singleLiquidation.entireTroveColl
		);
		singleLiquidation.SLSDGasCompensation = psyParams.SLSD_GAS_COMPENSATION(_asset);
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
			_SLSDInStabPool
		);

		troveManagerHelpers.closeTrove(
			_asset,
			_borrower,
			ITroveManagerHelpers.Status.closedByLiquidation
		);
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
		uint256 _SLSDInStabPool,
		uint256 _TCR,
		uint256 _price
	) internal returns (LiquidationValues memory singleLiquidation) {
		LocalVariables_InnerSingleLiquidateFunction memory vars;
		if (troveManagerHelpers.getTroveOwnersCount(_asset) <= 1) {
			return singleLiquidation;
		} // don't liquidate if last trove
		(
			singleLiquidation.entireTroveDebt,
			singleLiquidation.entireTroveColl,
			vars.pendingDebtReward,
			vars.pendingCollReward
		) = troveManagerHelpers.getEntireDebtAndColl(_asset, _borrower);

		singleLiquidation.collGasCompensation = _getCollGasCompensation(
			_asset,
			singleLiquidation.entireTroveColl
		);
		singleLiquidation.SLSDGasCompensation = psyParams.SLSD_GAS_COMPENSATION(_asset);
		vars.collToLiquidate = singleLiquidation.entireTroveColl.sub(
			singleLiquidation.collGasCompensation
		);

		// If ICR <= 100%, purely redistribute the Trove across all active Troves
		if (_ICR <= psyParams._100pct()) {
			troveManagerHelpers.movePendingTroveRewardsToActivePool(
				_asset,
				_activePool,
				_defaultPool,
				vars.pendingDebtReward,
				vars.pendingCollReward
			);
			troveManagerHelpers.removeStake(_asset, _borrower);

			singleLiquidation.debtToOffset = 0;
			singleLiquidation.collToSendToSP = 0;
			singleLiquidation.debtToRedistribute = singleLiquidation.entireTroveDebt;
			singleLiquidation.collToRedistribute = vars.collToLiquidate;

			troveManagerHelpers.closeTrove(
				_asset,
				_borrower,
				ITroveManagerHelpers.Status.closedByLiquidation
			);
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
		} else if ((_ICR > psyParams._100pct()) && (_ICR < psyParams.MCR(_asset))) {
			troveManagerHelpers.movePendingTroveRewardsToActivePool(
				_asset,
				_activePool,
				_defaultPool,
				vars.pendingDebtReward,
				vars.pendingCollReward
			);
			troveManagerHelpers.removeStake(_asset, _borrower);

			(
				singleLiquidation.debtToOffset,
				singleLiquidation.collToSendToSP,
				singleLiquidation.debtToRedistribute,
				singleLiquidation.collToRedistribute
			) = _getOffsetAndRedistributionVals(
				singleLiquidation.entireTroveDebt,
				vars.collToLiquidate,
				_SLSDInStabPool
			);

			troveManagerHelpers.closeTrove(
				_asset,
				_borrower,
				ITroveManagerHelpers.Status.closedByLiquidation
			);
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
			 * and there is SLSD in the Stability Pool, only offset, with no redistribution,
			 * but at a capped rate of 1.1 and only if the whole debt can be liquidated.
			 * The remainder due to the capped rate will be claimable as collateral surplus.
			 */
		} else if (
			(_ICR >= psyParams.MCR(_asset)) &&
			(_ICR < _TCR) &&
			(singleLiquidation.entireTroveDebt <= _SLSDInStabPool)
		) {
			troveManagerHelpers.movePendingTroveRewardsToActivePool(
				_asset,
				_activePool,
				_defaultPool,
				vars.pendingDebtReward,
				vars.pendingCollReward
			);
			assert(_SLSDInStabPool != 0);

			troveManagerHelpers.removeStake(_asset, _borrower);
			singleLiquidation = _getCappedOffsetVals(
				_asset,
				singleLiquidation.entireTroveDebt,
				singleLiquidation.entireTroveColl,
				_price
			);

			troveManagerHelpers.closeTrove(
				_asset,
				_borrower,
				ITroveManagerHelpers.Status.closedByLiquidation
			);
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
			// if (_ICR >= MCR && ( _ICR >= _TCR || singleLiquidation.entireTroveDebt > _SLSDInStabPool))
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
		uint256 _SLSDInStabPool
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
		if (_SLSDInStabPool > 0) {
			/*
			 * Offset as much debt & collateral as possible against the Stability Pool, and redistribute the remainder
			 * between all active troves.
			 *
			 *  If the trove's debt is larger than the deposited SLSD in the Stability Pool:
			 *
			 *  - Offset an amount of the trove's debt equal to the SLSD in the Stability Pool
			 *  - Send a fraction of the trove's collateral to the Stability Pool, equal to the fraction of its offset debt
			 *
			 */
			debtToOffset = PSYMath._min(_debt, _SLSDInStabPool);
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
		uint256 cappedCollPortion = _entireTroveDebt.mul(psyParams.MCR(_asset)).div(_price);

		singleLiquidation.collGasCompensation = _getCollGasCompensation(_asset, cappedCollPortion);
		singleLiquidation.SLSDGasCompensation = psyParams.SLSD_GAS_COMPENSATION(_asset);

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
		ContractsCache memory contractsCache = ContractsCache(
			psyParams.activePool(),
			psyParams.defaultPool(),
			ISLSDToken(address(0)),
			IPSYStaking(address(0)),
			sortedTroves,
			ICollSurplusPool(address(0)),
			address(0)
		);
		IStabilityPool stabilityPoolCached = stabilityPoolManager.getAssetStabilityPool(_asset);

		LocalVariables_OuterLiquidationFunction memory vars;

		LiquidationTotals memory totals;

		vars.price = psyParams.priceFeed().fetchPrice(_asset);
		vars.SLSDInStabPool = stabilityPoolCached.getTotalSLSDDeposits();
		vars.recoveryModeAtStart = troveManagerHelpers.checkRecoveryMode(_asset, vars.price);

		// Perform the appropriate liquidation sequence - tally the values, and obtain their totals
		if (vars.recoveryModeAtStart) {
			totals = _getTotalsFromLiquidateTrovesSequence_RecoveryMode(
				_asset,
				contractsCache,
				vars.price,
				vars.SLSDInStabPool,
				_n
			);
		} else {
			// if !vars.recoveryModeAtStart
			totals = _getTotalsFromLiquidateTrovesSequence_NormalMode(
				_asset,
				contractsCache.activePool,
				contractsCache.defaultPool,
				vars.price,
				vars.SLSDInStabPool,
				_n
			);
		}

		require(totals.totalDebtInSequence > 0, "0L");

		// Move liquidated ETH and SLSD to the appropriate pools
		stabilityPoolCached.offset(totals.totalDebtToOffset, totals.totalCollToSendToSP);
		troveManagerHelpers.redistributeDebtAndColl(
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
		troveManagerHelpers.updateSystemSnapshots_excludeCollRemainder(
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
			totals.totalSLSDGasCompensation
		);

		// Send gas compensation to caller
		_sendGasCompensation(
			_asset,
			contractsCache.activePool,
			msg.sender,
			totals.totalSLSDGasCompensation,
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
		uint256 _SLSDInStabPool,
		uint256 _n
	) internal returns (LiquidationTotals memory totals) {
		LocalVariables_AssetBorrowerPrice memory assetVars = LocalVariables_AssetBorrowerPrice(
			_asset,
			address(0),
			_price
		);

		LocalVariables_LiquidationSequence memory vars;
		LiquidationValues memory singleLiquidation;

		vars.remainingSLSDInStabPool = _SLSDInStabPool;
		vars.backToNormalMode = false;
		vars.entireSystemDebt = getEntireSystemDebt(assetVars._asset);
		vars.entireSystemColl = getEntireSystemColl(assetVars._asset);

		vars.user = _contractsCache.sortedTroves.getLast(assetVars._asset);
		address firstUser = _contractsCache.sortedTroves.getFirst(assetVars._asset);
		for (vars.i = 0; vars.i < _n && vars.user != firstUser; vars.i++) {
			// we need to cache it, because current user is likely going to be deleted
			address nextUser = _contractsCache.sortedTroves.getPrev(assetVars._asset, vars.user);

			vars.ICR = troveManagerHelpers.getCurrentICR(
				assetVars._asset,
				vars.user,
				assetVars._price
			);

			if (!vars.backToNormalMode) {
				// Break the loop if ICR is greater than MCR and Stability Pool is empty
				if (vars.ICR >= psyParams.MCR(_asset) && vars.remainingSLSDInStabPool == 0) {
					break;
				}

				uint256 TCR = PSYMath._computeCR(
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
					vars.remainingSLSDInStabPool,
					TCR,
					assetVars._price
				);

				// Update aggregate trackers
				vars.remainingSLSDInStabPool = vars.remainingSLSDInStabPool.sub(
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

				vars.backToNormalMode = !troveManagerHelpers._checkPotentialRecoveryMode(
					_asset,
					vars.entireSystemColl,
					vars.entireSystemDebt,
					assetVars._price
				);
			} else if (vars.backToNormalMode && vars.ICR < psyParams.MCR(_asset)) {
				singleLiquidation = _liquidateNormalMode(
					assetVars._asset,
					_contractsCache.activePool,
					_contractsCache.defaultPool,
					vars.user,
					vars.remainingSLSDInStabPool
				);

				vars.remainingSLSDInStabPool = vars.remainingSLSDInStabPool.sub(
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
		uint256 _SLSDInStabPool,
		uint256 _n
	) internal returns (LiquidationTotals memory totals) {
		LocalVariables_LiquidationSequence memory vars;
		LiquidationValues memory singleLiquidation;
		ISortedTroves sortedTrovesCached = sortedTroves;

		vars.remainingSLSDInStabPool = _SLSDInStabPool;

		for (vars.i = 0; vars.i < _n; vars.i++) {
			vars.user = sortedTrovesCached.getLast(_asset);
			vars.ICR = troveManagerHelpers.getCurrentICR(_asset, vars.user, _price);

			if (vars.ICR < psyParams.MCR(_asset)) {
				singleLiquidation = _liquidateNormalMode(
					_asset,
					_activePool,
					_defaultPool,
					vars.user,
					vars.remainingSLSDInStabPool
				);

				vars.remainingSLSDInStabPool = vars.remainingSLSDInStabPool.sub(
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
		require(_troveArray.length != 0, "CA");

		IActivePool activePoolCached = psyParams.activePool();
		IDefaultPool defaultPoolCached = psyParams.defaultPool();
		IStabilityPool stabilityPoolCached = stabilityPoolManager.getAssetStabilityPool(_asset);

		LocalVariables_OuterLiquidationFunction memory vars;
		LiquidationTotals memory totals;

		vars.SLSDInStabPool = stabilityPoolCached.getTotalSLSDDeposits();
		vars.price = psyParams.priceFeed().fetchPrice(_asset);

		vars.recoveryModeAtStart = _checkRecoveryMode(_asset, vars.price);

		// Perform the appropriate liquidation sequence - tally values and obtain their totals.
		if (vars.recoveryModeAtStart) {
			totals = _getTotalFromBatchLiquidate_RecoveryMode(
				_asset,
				activePoolCached,
				defaultPoolCached,
				vars.price,
				vars.SLSDInStabPool,
				_troveArray
			);
		} else {
			//  if !vars.recoveryModeAtStart
			totals = _getTotalsFromBatchLiquidate_NormalMode(
				_asset,
				activePoolCached,
				defaultPoolCached,
				vars.price,
				vars.SLSDInStabPool,
				_troveArray
			);
		}

		require(totals.totalDebtInSequence > 0, "0L");

		// Move liquidated ETH and SLSD to the appropriate pools
		stabilityPoolCached.offset(totals.totalDebtToOffset, totals.totalCollToSendToSP);
		troveManagerHelpers.redistributeDebtAndColl(
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
		troveManagerHelpers.updateSystemSnapshots_excludeCollRemainder(
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
			totals.totalSLSDGasCompensation
		);

		// Send gas compensation to caller
		_sendGasCompensation(
			_asset,
			activePoolCached,
			msg.sender,
			totals.totalSLSDGasCompensation,
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
		uint256 _SLSDInStabPool,
		address[] memory _troveArray
	) internal returns (LiquidationTotals memory totals) {
		LocalVariables_LiquidationSequence memory vars;
		LiquidationValues memory singleLiquidation;

		vars.remainingSLSDInStabPool = _SLSDInStabPool;
		vars.backToNormalMode = false;
		vars.entireSystemDebt = getEntireSystemDebt(_asset);
		vars.entireSystemColl = getEntireSystemColl(_asset);

		for (vars.i = 0; vars.i < _troveArray.length; vars.i++) {
			vars.user = _troveArray[vars.i];
			// Skip non-active troves
			if (troveManagerHelpers.getTroveStatus(_asset, vars.user) != 1) {
				continue;
			}

			vars.ICR = troveManagerHelpers.getCurrentICR(_asset, vars.user, _price);

			if (!vars.backToNormalMode) {
				// Skip this trove if ICR is greater than MCR and Stability Pool is empty
				if (vars.ICR >= psyParams.MCR(_asset) && vars.remainingSLSDInStabPool == 0) {
					continue;
				}

				uint256 TCR = PSYMath._computeCR(
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
					vars.remainingSLSDInStabPool,
					TCR,
					_price
				);

				// Update aggregate trackers
				vars.remainingSLSDInStabPool = vars.remainingSLSDInStabPool.sub(
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

				vars.backToNormalMode = !troveManagerHelpers._checkPotentialRecoveryMode(
					_asset,
					vars.entireSystemColl,
					vars.entireSystemDebt,
					_price
				);
			} else if (vars.backToNormalMode && vars.ICR < psyParams.MCR(_asset)) {
				singleLiquidation = _liquidateNormalMode(
					_asset,
					_activePool,
					_defaultPool,
					vars.user,
					vars.remainingSLSDInStabPool
				);
				vars.remainingSLSDInStabPool = vars.remainingSLSDInStabPool.sub(
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
		uint256 _SLSDInStabPool,
		address[] memory _troveArray
	) internal returns (LiquidationTotals memory totals) {
		LocalVariables_LiquidationSequence memory vars;
		LiquidationValues memory singleLiquidation;

		vars.remainingSLSDInStabPool = _SLSDInStabPool;

		for (vars.i = 0; vars.i < _troveArray.length; vars.i++) {
			vars.user = _troveArray[vars.i];
			vars.ICR = troveManagerHelpers.getCurrentICR(_asset, vars.user, _price);

			if (vars.ICR < psyParams.MCR(_asset)) {
				singleLiquidation = _liquidateNormalMode(
					_asset,
					_activePool,
					_defaultPool,
					vars.user,
					vars.remainingSLSDInStabPool
				);
				vars.remainingSLSDInStabPool = vars.remainingSLSDInStabPool.sub(
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
		newTotals.totalSLSDGasCompensation = oldTotals.totalSLSDGasCompensation.add(
			singleLiquidation.SLSDGasCompensation
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
		uint256 _SLSD,
		uint256 _ETH
	) internal {
		if (_SLSD > 0) {
			slsdToken.returnFromPool(gasPoolAddress, _liquidator, _SLSD);
		}

		if (_ETH > 0) {
			_activePool.sendAsset(_asset, _liquidator, _ETH);
		}
	}

	// --- Redemption functions ---

	// Redeem as much collateral as possible from _borrower's Trove in exchange for SLSD up to _maxSLSDamount
	function _redeemCollateralFromTrove(
		address _asset,
		ContractsCache memory _contractsCache,
		address _borrower,
		uint256 _maxSLSDamount,
		uint256 _price,
		address _upperPartialRedemptionHint,
		address _lowerPartialRedemptionHint,
		uint256 _partialRedemptionHintNICR
	) internal returns (SingleRedemptionValues memory singleRedemption) {
		LocalVariables_AssetBorrowerPrice memory vars = LocalVariables_AssetBorrowerPrice(
			_asset,
			_borrower,
			_price
		);

		// Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the Trove minus the liquidation reserve
		singleRedemption.SLSDLot = PSYMath._min(
			_maxSLSDamount,
			troveManagerHelpers.getTroveDebt(vars._asset, vars._borrower).sub(
				psyParams.SLSD_GAS_COMPENSATION(_asset)
			)
		);

		// Get the ETHLot of equivalent value in USD
		singleRedemption.ETHLot = singleRedemption.SLSDLot.mul(DECIMAL_PRECISION).div(_price);

		// Decrease the debt and collateral of the current Trove according to the SLSD lot and corresponding ETH to send
		uint256 newDebt = (troveManagerHelpers.getTroveDebt(vars._asset, vars._borrower)).sub(
			singleRedemption.SLSDLot
		);
		uint256 newColl = (troveManagerHelpers.getTroveColl(vars._asset, vars._borrower)).sub(
			singleRedemption.ETHLot
		);

		if (newDebt == psyParams.SLSD_GAS_COMPENSATION(_asset)) {
			// No debt left in the Trove (except for the liquidation reserve), therefore the trove gets closed
			troveManagerHelpers.removeStake(vars._asset, vars._borrower);
			troveManagerHelpers.closeTrove(
				vars._asset,
				vars._borrower,
				ITroveManagerHelpers.Status.closedByRedemption
			);
			_redeemCloseTrove(
				vars._asset,
				_contractsCache,
				vars._borrower,
				psyParams.SLSD_GAS_COMPENSATION(vars._asset),
				newColl
			);
			emit TroveUpdated(
				vars._asset,
				vars._borrower,
				0,
				0,
				0,
				TroveManagerOperation.redeemCollateral
			);
		} else {
			uint256 newNICR = PSYMath._computeNominalCR(newColl, newDebt);

			/*
			 * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
			 * certainly result in running out of gas.
			 *
			 * If the resultant net debt of the partial is less than the minimum, net debt we bail.
			 */
			if (
				newNICR != _partialRedemptionHintNICR ||
				_getNetDebt(vars._asset, newDebt) < psyParams.MIN_NET_DEBT(vars._asset)
			) {
				singleRedemption.cancelledPartial = true;
				return singleRedemption;
			}

			_contractsCache.sortedTroves.reInsert(
				vars._asset,
				vars._borrower,
				newNICR,
				_upperPartialRedemptionHint,
				_lowerPartialRedemptionHint
			);

			troveManagerHelpers.setTroveDeptAndColl(vars._asset, vars._borrower, newDebt, newColl);
			troveManagerHelpers.updateStakeAndTotalStakes(vars._asset, vars._borrower);

			emit TroveUpdated(
				vars._asset,
				vars._borrower,
				newDebt,
				newColl,
				troveManagerHelpers.getTroveStake(vars._asset, vars._borrower),
				TroveManagerOperation.redeemCollateral
			);
		}

		return singleRedemption;
	}

	/*
	 * Called when a full redemption occurs, and closes the trove.
	 * The redeemer swaps (debt - liquidation reserve) SLSD for (debt - liquidation reserve) worth of ETH, so the SLSD liquidation reserve left corresponds to the remaining debt.
	 * In order to close the trove, the SLSD liquidation reserve is burned, and the corresponding debt is removed from the active pool.
	 * The debt recorded on the trove's struct is zero'd elswhere, in _closeTrove.
	 * Any surplus ETH left in the trove, is sent to the Coll surplus pool, and can be later claimed by the borrower.
	 */
	function _redeemCloseTrove(
		address _asset,
		ContractsCache memory _contractsCache,
		address _borrower,
		uint256 _SLSD,
		uint256 _ETH
	) internal {
		_contractsCache.slsdToken.burn(gasPoolAddress, _SLSD);
		// Update Active Pool SLSD, and send ETH to account
		_contractsCache.activePool.decreaseSLSDDebt(_asset, _SLSD);

		// send ETH from Active Pool to CollSurplus Pool
		_contractsCache.collSurplusPool.accountSurplus(_asset, _borrower, _ETH);
		_contractsCache.activePool.sendAsset(
			_asset,
			address(_contractsCache.collSurplusPool),
			_ETH
		);
	}

	function _isValidFirstRedemptionHint(
		address _asset,
		ISortedTroves _sortedTroves,
		address _firstRedemptionHint,
		uint256 _price
	) internal view returns (bool) {
		if (
			_firstRedemptionHint == address(0) ||
			!_sortedTroves.contains(_asset, _firstRedemptionHint) ||
			troveManagerHelpers.getCurrentICR(_asset, _firstRedemptionHint, _price) <
			psyParams.MCR(_asset)
		) {
			return false;
		}

		address nextTrove = _sortedTroves.getNext(_asset, _firstRedemptionHint);
		return
			nextTrove == address(0) ||
			troveManagerHelpers.getCurrentICR(_asset, nextTrove, _price) < psyParams.MCR(_asset);
	}

	function setRedemptionWhitelistStatus(bool _status) external onlyOwner {
		isRedemptionWhitelisted = _status;
	}

	function addUserToWhitelistRedemption(address _user) external onlyOwner {
		redemptionWhitelist[_user] = true;
	}

	function removeUserFromWhitelistRedemption(address _user) external onlyOwner {
		delete redemptionWhitelist[_user];
	}

	/* Send _SLSDamount SLSD to the system and redeem the corresponding amount of collateral from as many Troves as are needed to fill the redemption
	 * request.  Applies pending rewards to a Trove before reducing its debt and coll.
	 *
	 * Note that if _amount is very large, this function can run out of gas, specially if traversed troves are small. This can be easily avoided by
	 * splitting the total _amount in appropriate chunks and calling the function multiple times.
	 *
	 * Param `_maxIterations` can also be provided, so the loop through Troves is capped (if it’s zero, it will be ignored).This makes it easier to
	 * avoid OOG for the frontend, as only knowing approximately the average cost of an iteration is enough, without needing to know the “topology”
	 * of the trove list. It also avoids the need to set the cap in stone in the contract, nor doing gas calculations, as both gas price and opcode
	 * costs can vary.
	 *
	 * All Troves that are redeemed from -- with the likely exception of the last one -- will end up with no debt left, therefore they will be closed.
	 * If the last Trove does have some remaining debt, it has a finite ICR, and the reinsertion could be anywhere in the list, therefore it requires a hint.
	 * A frontend should use getRedemptionHints() to calculate what the ICR of this Trove will be after redemption, and pass a hint for its position
	 * in the sortedTroves list along with the ICR value that the hint was found for.
	 *
	 * If another transaction modifies the list between calling getRedemptionHints() and passing the hints to redeemCollateral(), it
	 * is very likely that the last (partially) redeemed Trove would end up with a different ICR than what the hint is for. In this case the
	 * redemption will stop after the last completely redeemed Trove and the sender will keep the remaining SLSD amount, which they can attempt
	 * to redeem later.
	 */
	function redeemCollateral(
		address _asset,
		uint256 _SLSDamount,
		address _firstRedemptionHint,
		address _upperPartialRedemptionHint,
		address _lowerPartialRedemptionHint,
		uint256 _partialRedemptionHintNICR,
		uint256 _maxIterations,
		uint256 _maxFeePercentage
	) external override {
		if (isRedemptionWhitelisted) {
			require(redemptionWhitelist[msg.sender], "NW");
		}

		require(block.timestamp >= psyParams.redemptionBlock(_asset), "BR");

		ContractsCache memory contractsCache = ContractsCache(
			psyParams.activePool(),
			psyParams.defaultPool(),
			slsdToken,
			psyStaking,
			sortedTroves,
			collSurplusPool,
			gasPoolAddress
		);
		RedemptionTotals memory totals;

		troveManagerHelpers._requireValidMaxFeePercentage(_asset, _maxFeePercentage);
		totals.price = psyParams.priceFeed().fetchPrice(_asset);
		troveManagerHelpers._requireTCRoverMCR(_asset, totals.price);
		troveManagerHelpers._requireAmountGreaterThanZero(_SLSDamount);
		troveManagerHelpers._requireSLSDBalanceCoversRedemption(
			contractsCache.slsdToken,
			msg.sender,
			_SLSDamount
		);

		totals.totalSLSDSupplyAtStart = getEntireSystemDebt(_asset);
		totals.remainingSLSD = _SLSDamount;
		address currentBorrower;

		if (
			_isValidFirstRedemptionHint(
				_asset,
				contractsCache.sortedTroves,
				_firstRedemptionHint,
				totals.price
			)
		) {
			currentBorrower = _firstRedemptionHint;
		} else {
			currentBorrower = contractsCache.sortedTroves.getLast(_asset);
			// Find the first trove with ICR >= MCR
			while (
				currentBorrower != address(0) &&
				troveManagerHelpers.getCurrentICR(_asset, currentBorrower, totals.price) <
				psyParams.MCR(_asset)
			) {
				currentBorrower = contractsCache.sortedTroves.getPrev(_asset, currentBorrower);
			}
		}

		// Loop through the Troves starting from the one with lowest collateral ratio until _amount of SLSD is exchanged for collateral
		if (_maxIterations == 0) {
			_maxIterations = type(uint256).max;
		}
		while (currentBorrower != address(0) && totals.remainingSLSD > 0 && _maxIterations > 0) {
			_maxIterations--;
			// Save the address of the Trove preceding the current one, before potentially modifying the list
			address nextUserToCheck = contractsCache.sortedTroves.getPrev(_asset, currentBorrower);

			troveManagerHelpers.applyPendingRewards(
				_asset,
				contractsCache.activePool,
				contractsCache.defaultPool,
				currentBorrower
			);

			SingleRedemptionValues memory singleRedemption = _redeemCollateralFromTrove(
				_asset,
				contractsCache,
				currentBorrower,
				totals.remainingSLSD,
				totals.price,
				_upperPartialRedemptionHint,
				_lowerPartialRedemptionHint,
				_partialRedemptionHintNICR
			);

			if (singleRedemption.cancelledPartial) break; // Partial redemption was cancelled (out-of-date hint, or new net debt < minimum), therefore we could not redeem from the last Trove

			totals.totalSLSDToRedeem = totals.totalSLSDToRedeem.add(singleRedemption.SLSDLot);
			totals.totalAssetDrawn = totals.totalAssetDrawn.add(singleRedemption.ETHLot);

			totals.remainingSLSD = totals.remainingSLSD.sub(singleRedemption.SLSDLot);
			currentBorrower = nextUserToCheck;
		}
		require(totals.totalAssetDrawn > 0, "UR");
		
		// Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
		// Use the saved total SLSD supply value, from before it was reduced by the redemption.
		troveManagerHelpers.updateBaseRateFromRedemption(
			_asset,
			totals.totalAssetDrawn,
			totals.price,
			totals.totalSLSDSupplyAtStart
		);

		
		// Calculate the ETH fee	
		totals.ETHFee = troveManagerHelpers._getRedemptionFee(_asset, totals.totalAssetDrawn);
		_requireUserAcceptsFee(totals.ETHFee, totals.totalAssetDrawn, _maxFeePercentage);
		
		if (isPSYReady) {	
			// Send the ETH fee to the PSY staking contract
			contractsCache.activePool.sendAsset(
				_asset,
				address(contractsCache.psyStaking),
				totals.ETHFee
			);
			contractsCache.psyStaking.increaseF_Asset(_asset, totals.ETHFee);
		} else {
			contractsCache.activePool.sendAsset(
				_asset,
				treasury,
				totals.ETHFee
			);
		}
		
		totals.ETHToSendToRedeemer = totals.totalAssetDrawn.sub(totals.ETHFee);

		emit Redemption(
			_asset,
			_SLSDamount,
			totals.totalSLSDToRedeem,
			totals.totalAssetDrawn,
			totals.ETHFee
		);

		// Burn the total SLSD that is cancelled with debt, and send the redeemed ETH to msg.sender
		contractsCache.slsdToken.burn(msg.sender, totals.totalSLSDToRedeem);
		// Update Active Pool SLSD, and send ETH to account
		contractsCache.activePool.decreaseSLSDDebt(_asset, totals.totalSLSDToRedeem);
		contractsCache.activePool.sendAsset(_asset, msg.sender, totals.ETHToSendToRedeemer);
	}

	/*
	 * Add PSY token modules later if it is not added at launch
	 */
	function addPSYModules(address _PSYStakingAddress) external onlyOwner {
		require(!isPSYReady,"PSY modules already registered");
		psyStaking = IPSYStaking(_PSYStakingAddress);
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
}

