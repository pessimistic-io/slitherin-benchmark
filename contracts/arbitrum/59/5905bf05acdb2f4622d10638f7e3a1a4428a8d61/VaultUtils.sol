// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IVault } from "./IVault.sol";
import { IVaultUtils } from "./IVaultUtils.sol";

/**
 * Deployed by Vesta because we needed this little helper
 * There's no ownership attach to it.
 *
 * We didn't modify the core logic whatsoever, we just removed the functions that we do not need
 *
 * Ref: https://github.com/gmx-io/gmx-contracts/blob/master/contracts/core/VaultUtils.sol
 * Commit Id: 1a901D0
 */
contract VaultUtils is IVaultUtils {
	IVault public vault;

	uint256 public constant BASIS_POINTS_DIVISOR = 10000;
	uint256 public constant FUNDING_RATE_PRECISION = 1000000;

	constructor(address _vault) {
		require(_vault != address(0), "Invalid Vault Address");
		vault = IVault(_vault);
	}

	function getBuyUsdgFeeBasisPoints(address _token, uint256 _usdgAmount)
		public
		view
		override
		returns (uint256)
	{
		return
			getFeeBasisPoints(
				_token,
				_usdgAmount,
				vault.mintBurnFeeBasisPoints(),
				vault.taxBasisPoints(),
				true
			);
	}

	function getSellUsdgFeeBasisPoints(address _token, uint256 _usdgAmount)
		public
		view
		override
		returns (uint256)
	{
		return
			getFeeBasisPoints(
				_token,
				_usdgAmount,
				vault.mintBurnFeeBasisPoints(),
				vault.taxBasisPoints(),
				false
			);
	}

	function getSwapFeeBasisPoints(
		address _tokenIn,
		address _tokenOut,
		uint256 _usdgAmount
	) public view override returns (uint256) {
		bool isStableSwap = vault.stableTokens(_tokenIn) &&
			vault.stableTokens(_tokenOut);

		uint256 baseBps = isStableSwap
			? vault.stableSwapFeeBasisPoints()
			: vault.swapFeeBasisPoints();
		uint256 taxBps = isStableSwap
			? vault.stableTaxBasisPoints()
			: vault.taxBasisPoints();
		uint256 feesBasisPoints0 = getFeeBasisPoints(
			_tokenIn,
			_usdgAmount,
			baseBps,
			taxBps,
			true
		);
		uint256 feesBasisPoints1 = getFeeBasisPoints(
			_tokenOut,
			_usdgAmount,
			baseBps,
			taxBps,
			false
		);
		// use the higher of the two fee basis points
		return feesBasisPoints0 > feesBasisPoints1 ? feesBasisPoints0 : feesBasisPoints1;
	}

	// cases to consider
	// 1. initialAmount is far from targetAmount, action increases balance slightly => high rebate
	// 2. initialAmount is far from targetAmount, action increases balance largely => high rebate
	// 3. initialAmount is close to targetAmount, action increases balance slightly => low rebate
	// 4. initialAmount is far from targetAmount, action reduces balance slightly => high tax
	// 5. initialAmount is far from targetAmount, action reduces balance largely => high tax
	// 6. initialAmount is close to targetAmount, action reduces balance largely => low tax
	// 7. initialAmount is above targetAmount, nextAmount is below targetAmount and vice versa
	// 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
	function getFeeBasisPoints(
		address _token,
		uint256 _usdgDelta,
		uint256 _feeBasisPoints,
		uint256 _taxBasisPoints,
		bool _increment
	) public view override returns (uint256) {
		if (!vault.hasDynamicFees()) {
			return _feeBasisPoints;
		}

		uint256 initialAmount = vault.usdgAmounts(_token);
		uint256 nextAmount = initialAmount + _usdgDelta;
		if (!_increment) {
			nextAmount = _usdgDelta > initialAmount ? 0 : initialAmount - _usdgDelta;
		}

		uint256 targetAmount = vault.getTargetUsdgAmount(_token);
		if (targetAmount == 0) {
			return _feeBasisPoints;
		}

		uint256 initialDiff = initialAmount > targetAmount
			? initialAmount - targetAmount
			: targetAmount - initialAmount;
		uint256 nextDiff = nextAmount > targetAmount
			? nextAmount - targetAmount
			: targetAmount - nextAmount;

		// action improves relative asset balance
		if (nextDiff < initialDiff) {
			uint256 rebateBps = (_taxBasisPoints * initialDiff) / targetAmount;
			return rebateBps > _feeBasisPoints ? 0 : _feeBasisPoints - rebateBps;
		}

		uint256 averageDiff = (initialDiff + nextDiff) / 2;
		if (averageDiff > targetAmount) {
			averageDiff = targetAmount;
		}
		uint256 taxBps = (_taxBasisPoints * averageDiff) / targetAmount;
		return _feeBasisPoints + taxBps;
	}
}


