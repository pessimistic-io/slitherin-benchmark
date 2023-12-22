// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Math.sol";
import "./IAllocator.sol";
import "./ISwapManager.sol";
import "./Manageable.sol";

abstract contract StrategyV4 is Manageable {
	using SafeERC20 for IERC20;
	using Address for address;

	event Compound(uint256 newDebt, uint256 block);
	event chargedFees(uint256 amount);
	event FeesUpdated(uint256 newFee);
	event RouterUpdated(address indexed newRouter);
	event feeRecipientUpdated(address indexed newFeeRecipient);
	event MaxSlippageUpdated(uint256 newMaxSlippage);

	uint256 constant DENOMINATOR = 1000;
	uint256 constant ZERO = 0;
	uint256 constant MAX_INT = 2 ** 256 - 1;

	address public immutable allocator;
	address public immutable asset;

	uint256 public lastHarvest;
	uint256 public vaultDebt;

	// params
	uint256 public feeAmount; // 1% = 10
	address public feeRecipient;
	uint256 public maxSlippage; // 1% = 10
	ISwapManager public swapManager;

	error notAuthorized();
	error feeTooHigh();
	error minAmountTooHigh();
	error maxSlippageTooHigh();
	error addressZero();
	error wrongToken();

	constructor(
		uint256 _feeAmount,
		address _asset,
		address _allocator,
		address _feeRecipient
	) {
		feeAmount = _feeAmount;
		asset = _asset;
		allocator = _allocator;
		feeRecipient = _feeRecipient;
		maxSlippage = 50;

		IERC20(_asset).safeApprove(_allocator, MAX_INT);
	}

	modifier onlyInternal() {
		internalCheck();
		_;
	}

	function internalCheck() internal view {
		if (!hasRole(KEEPER_ROLE, msg.sender) && msg.sender != allocator)
			revert notAuthorized();
	}

	/// @notice Order to unfold the strategy
	/// If we pass "panic", we ignore slippage and withdraw all
	/// @dev The call will revert if the slippage created is too high
	/// @param _amount Amount of debt to unfold
	/// @param _panic ignore slippage when unfolding
	function liquidate(
		uint256 _amount,
		uint256 _minAmountOut,
		bool _panic
	) external onlyInternal returns (uint256 assetsRecovered, uint256 newDebt) {
		// Recovering values
		uint256 balance = IERC20(asset).balanceOf(address(this));
		uint256 totalAssets = _investedInPool() + balance;

		// If we have less assets than the amount requested, we withdraw all
		if (totalAssets < _amount) {
			_amount = totalAssets;
		}

		// If we have enough idle assets, just return them
		if (balance > _amount) {
			// If the call is not coming from the allocator, we update the debt registered
			if (msg.sender != allocator) {
				IAllocator(allocator).updateStrategyDebt(totalAssets - _amount);
			}

			// Send assets
			IERC20(asset).safeTransfer({ to: allocator, value: _amount });
			return (_amount, totalBalance());
		} else if (balance > 0) {
			assetsRecovered = balance;
			_amount -= balance;
		}

		// In case of "panic" we withdraw all
		if (_panic) _amount = _investedInPool();

		// Unstake from protocol
		assetsRecovered += _liquidate(_amount);

		// Check that we have enough assets to return
		if ((assetsRecovered < _minAmountOut) && !_panic)
			revert minAmountTooHigh();

		// Update the debt registered
		if (msg.sender != allocator)
			IAllocator(allocator).updateStrategyDebt(
				totalBalance() - assetsRecovered
			);

		// Send assets
		IERC20(asset).safeTransfer({ to: allocator, value: assetsRecovered });

		// Return assets recovered and new debt
		return (assetsRecovered, totalBalance());
	}

	/// @notice Order the withdraw request in strategies with lock
	/// @param _amount Amount of debt to unfold
	/// @return assetsRecovered Amount of assets recovered
	function withdrawRequest(
		uint256 _amount
	) external onlyInternal returns (uint256) {
		return _withdrawRequest(_amount);
	}

	/**
			@notice Harvest, convert rewards and deposit, and update the home chain router with the new amount.
			@dev Deposits are done during compound to save gas. In order to minimize slippage, we can specify a
			max amount of assets to deposit during the compound phase.

			We can also specify extra params for the pipeline, for instance, the min amount of LP tokens to
			receive in order to avoid front-running. Those params are passed as bytes, and the pipeline will
			decode them.

			The strategy will also return pipeline-specific values as `paramEstimation`, which can be gathered
			beforehand with ethers.callStatic, and then passed to the strategy as `params` to avoid front-running.

			@param _harvest Allows the caller to specify if harvest happens - otherwise, only deposit+update
			@param maxDeposit Max amount of assets to deposit during the compound phase
			@param _params Extra params for the pipeline - for instance, the min amount of LP tokens to receive
			@return newDebt New amount of debt in the strategy
			@return paramsEstimation The return values of the pipeline - for instance, the amount of LP tokens received
	*/
	function harvestCompoundUpdate(
		bool _harvest,
		uint256 maxDeposit,
		bytes memory _params
	)
		external
		onlyKeeper
		returns (uint256 newDebt, bytes memory paramsEstimation)
	{
		paramsEstimation = _harvestCompound(_harvest, maxDeposit, _params);
		newDebt = totalBalance();
		IAllocator(allocator).updateStrategyDebt(newDebt);
		emit Compound(newDebt, block.timestamp);
		return (newDebt, paramsEstimation);
	}

	/// @notice setter for fees
	/// @param _feeAmount fee, as x/1000 - 200/1000 = 20%
	function updateFee(uint256 _feeAmount) external onlyAdmin {
		if (_feeAmount > 200) revert feeTooHigh();
		feeAmount = _feeAmount;
		emit FeesUpdated(_feeAmount);
	}

	/// @notice Update Fee Recipient address
	function updateFeeRecipient(address _feeRecipient) external onlyAdmin {
		if (_feeRecipient == address(0)) revert addressZero();
		feeRecipient = _feeRecipient;
		emit feeRecipientUpdated(feeRecipient);
	}

	/// @notice recover tokens sent by error to the contract
	/// @param _token ERC40 token address
	function inCaseTokensGetStuck(address _token) external onlyAdmin {
		if (_token == address(asset)) revert wrongToken();

		uint256 amount = IERC20(_token).balanceOf(address(this));
		IERC20(_token).safeTransfer(msg.sender, amount);
	}

	// Views

	/**
	 * @notice amount of assets available and not yet deposited
	 * @return amount of assets available
	 */
	function available() public view returns (uint256) {
		return IERC20(asset).balanceOf(address(this));
	}

	/**
	 * @notice amount of reward tokens available and not yet harvested
	 * @dev abstract function to be implemented by the pipeline
	 * @return rewardAmounts amount of reward tokens available
	 */
	function rewardsAvailable()
		external
		view
		returns (uint256[] memory rewardAmounts)
	{
		return _rewardsAvailable();
	}

	/**
	 * @notice amount of assets in the protocol farmed by the strategy
	 * @dev underlying abstract function to be implemented by the pipeline
	 * @return amount of assets in the pool
	 */
	function investedInPool() public view returns (uint256) {
		return _investedInPool();
	}

	/**
	 * @notice total amount of assets available in the strategy
	 * @dev includes assets in the pool and assets available
	 * @return total amount of assets available in the strategy
	 */
	function totalBalance() public view returns (uint256) {
		return IERC20(asset).balanceOf(address(this)) + investedInPool();
	}

	/**
	 * @notice Update the swap manager
	 * @param _swapManager address of the new swap manager
	 */
	function updateSwapManager(address _swapManager) external onlyAdmin {
		if (_swapManager == address(0)) revert addressZero();
		swapManager = ISwapManager(_swapManager);
		emit RouterUpdated(_swapManager);
	}

	/// @notice remove allowances for safety
	function removeAllowances() external onlyManager {
		return _removeAllowances();
	}

	// Views

	/// Abstract functions to be implemented by the pipeline

	/**
	 * @notice withdraw assets from the protocol
	 * @param _amount amount of assets to withdraw
	 * @return  assetsRecovered amount of assets withdrawn
	 */
	function _liquidate(
		uint256 _amount
	) internal virtual returns (uint256 assetsRecovered) {}

	function _withdrawRequest(
		uint256 _amount
	) internal virtual returns (uint256) {}

	function _harvestCompound(
		bool _harvest,
		uint256 maxDeposit,
		bytes memory params
	) internal virtual returns (bytes memory paramsEstimation) {}

	function _investedInPool() internal view virtual returns (uint256) {}

	function _rewardsAvailable()
		internal
		view
		virtual
		returns (uint256[] memory rewardAmounts)
	{}

	function _giveAllowances() internal virtual {}

	function _removeAllowances() internal virtual {}

	function _chargeFees(address _feeRecipient) internal virtual {}

	function _swapRewards() internal virtual {}

	function _swapRewards(
		uint256[] memory _minAmountsOut
	) internal virtual returns (uint256[] memory amountsOut) {}
}

