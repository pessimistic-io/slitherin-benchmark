// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./SafeERC20.sol";
import "./IGlpAdapter.sol";
import "./IJonesGlpVaultRouter.sol";
import "./IJonesUsdcVault.sol";
import "./StrategyV4.sol";

/// @title JonesDAO Pipeline (v4)
/// @notice This contract is a pipeline for JonesDAO
/// @dev Basic implementation
contract JonesDAOPipeline is StrategyV4 {
	using SafeERC20 for IERC20;

	// Third party contracts
	address public glpAdapter;
	address public vaultRouter;
	address public stableVault;
	address public receiptToken;

	event WithdrawRequest(uint256 amount, uint256 epochStart);

	error NotEnoughShares(uint256 minAmount, uint256 sharesMinted);

	constructor(
		address _glpAdapter,
		address _vaultRouter,
		address _stableVault,
		address _receiptToken,
		uint256 _feeAmount,
		address _asset,
		address _allocator,
		address _feeRecipient
	) StrategyV4(_feeAmount, _asset, _allocator, _feeRecipient) {
		glpAdapter = _glpAdapter;
		vaultRouter = _vaultRouter;
		stableVault = _stableVault;
		receiptToken = _receiptToken;
		_giveAllowances();
	}

	// Interactions

	/** @notice Check rewards, take fees, swap to asset, deposit asset to liquidity pool, then
	 *		 lpToken to the rewardGauge.
	 *   @dev Pipeline will still execute if there are no assets to deposit allowing for seamless
	 *		Allocator update even if the pipeline is empty.
	 *		@param _harvest the bool signaling the function to compound rewards.
	 *		@param _maxDeposit the maximum amount of asset to deposit.
	 *		@param _params the bytes array containing the minimum amount of lp tokens to mint.
	 *      and the minimum assets out from swapping the rewards (if provided).
	 *		@return paramsEstimation bytes containing the amount of lp tokens received from the
	 * 	    deposit and the amounts of asset received after the rewards (uint256,uint256[] => bytes).	 */
	function _harvestCompound(
		bool _harvest,
		uint256 _maxDeposit,
		bytes memory _params
	) internal override returns (bytes memory paramsEstimation) {
		uint256 minLpOut;

		minLpOut = abi.decode(_params, (uint256));

		uint256 assetBal = IERC20(asset).balanceOf(address(this));
		// The amount to deposit is capped by the maxDeposit
		assetBal = assetBal > _maxDeposit ? _maxDeposit : assetBal;
		uint256 sharesMinted;
		if (assetBal > 0) {
			// Deposit asset to the vault
			sharesMinted = IGlpAdapter(glpAdapter).depositStable(
				assetBal,
				true
			);
			if (sharesMinted < minLpOut) {
				// If the amount of shares minted is less than the minimum amount of shares
				// to mint, revert the transaction.
				revert NotEnoughShares(
					abi.decode(_params, (uint256)),
					sharesMinted
				);
			}
		}
		return abi.encode(sharesMinted);
		/* Pipeline will still execute if there are no assets to deposit
		allowing for seamless Allocator update even if the pipeline is empty */
	}

	// Utils

	/// @notice Give allowances to the contracts used by the pipeline.
	function _giveAllowances() internal override {
		IERC20(asset).safeApprove({
			spender: glpAdapter,
			value: type(uint256).max
		});
	}

	/// @notice Remove allowances to the contracts used by the pipeline.
	function _removeAllowances() internal override {
		IERC20(asset).safeApprove({ spender: glpAdapter, value: 0 });
	}

	/// @param _amount The amount of shares to withdraw
	/// @notice Request withdrawal
	function _withdrawRequest(
		uint256 _amount
	) internal override returns (uint256) {
		// Prevent withdrawing more than invested
		if (_amount > investedInPool()) {
			_amount = investedInPool();
		}
		// Make the withdraw request in shares, retrieve the target epoch
		uint256 targetEpoch = IJonesGlpVaultRouter(vaultRouter)
			.stableWithdrawalSignal(
				IJonesUsdcVault(stableVault).convertToShares(_amount),
				true
			);
		// Emit withdraw request event
		emit WithdrawRequest(_amount, targetEpoch);
		return (_amount);
	}

	/// @param _amount The amount of asset to withdraw
	/// @notice Withdraw asset function, can remove all funds in case of emergency
	function _liquidate(
		uint256 _amount
	) internal override returns (uint256 assetsRecovered) {
		return
			IJonesGlpVaultRouter(vaultRouter).redeemStable(
				IJonesGlpVaultRouter(vaultRouter).currentEpoch()
			);
	}

	// Getters

	/// @notice Returns the investment in the pool.
	function _investedInPool() internal view override returns (uint256) {
		return IJonesUsdcVault(stableVault).convertToAssets(_stakedLPBalance());
	}

	/// @notice Returns the investment in lp token.
	function _stakedLPBalance() internal view returns (uint256) {
		return IERC20(receiptToken).balanceOf(address(this));
	}
}

