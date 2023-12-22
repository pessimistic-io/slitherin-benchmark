// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IVault.sol";
import "./AccessControlBase.sol";

contract FeeStrategy is AccessControlBase {
	/*==================================================== Events =============================================================*/

	event FeeMultiplierChanged(uint256 multiplier);

	event ConfigUpdated(uint256 maxMultiplier, uint256 minMultiplier);

	/*==================================================== State Variables ====================================================*/

	struct Config {
		uint256 minMultiplier;
		uint256 maxMultiplier;
	}

	struct LastDayReserves {
		uint256 profit;
		uint256 loss;
	}

	Config public config = Config(7_500_000_000_000_000, 12_500_000_000_000_000);

	/// @notice Last calculated multipliers index id
	uint256 public lastCalculatedIndex = 0;
	/// @notice Start time of periods
	uint256 public periodStartTime = block.timestamp - 1 days;
	/// @notice Last calculated multiplier
	uint256 public currentMultiplier;
	/// @notice Vault address
	IVault public vault;
	/// @notice stores the profit and loss of the last day for each token
	mapping(address => LastDayReserves) public lastDayReserves;

	/*==================================================== Constant Variables ==================================================*/

	/// @notice used to calculate precise decimals
	uint256 private constant PRECISION = 1e18;

	/*==================================================== FUNCTIONS ===========================================================*/

	constructor(
		IVault _vault,
		address _vaultRegistry,
		address _timelock
	) AccessControlBase(_vaultRegistry, _timelock) {
		require(address(_vault) != address(0), "Vault address zero");
		vault = _vault;
		currentMultiplier = config.maxMultiplier;
	}

	/**
	 *
	 * @param _config max, min multipliers
	 * @notice funtion to set new max min multipliers config
	 */
	function updateConfig(Config memory _config) public onlyGovernance {
		require(_config.maxMultiplier != 0, "Max zero");
		require(_config.minMultiplier != 0, "Min zero");
		require(_config.minMultiplier < _config.maxMultiplier, "Min greater than max");

		config.maxMultiplier = _config.maxMultiplier;
		config.minMultiplier = _config.minMultiplier;

		emit ConfigUpdated(_config.maxMultiplier, _config.minMultiplier);
	}

	/**
	 * @param _vault address of vault
	 * @notice function to set vault address
	 */
	function setVault(IVault _vault) public onlyGovernance {
		require(address(_vault) != address(0), "vault zero address");
		vault = _vault;
	}

	/**
	 * @param _wagerFee wager fee percentage in 1e18
	 * @notice function to set wager fee to vault for a given day
	 */
	function _setWagerFee(uint256 _wagerFee) internal {
		currentMultiplier = _wagerFee;
		vault.setWagerFee(_wagerFee);
		emit FeeMultiplierChanged(currentMultiplier);
	}

	/**
	 * @dev Public function to calculate the dollar value of a given token amount.
	 * @param _token The address of the whitelisted token on the vault.
	 * @param _amount The amount of the given token.
	 * @return dollarValue_ The dollar value of the given token amount.
	 * @notice This function takes the address of a whitelisted token on the vault and an amount of that token,
	 *  and calculates the dollar value of that amount by multiplying the amount by the current dollar value of the token
	 *  on the vault and dividing by 10^decimals of the token. The result is then divided by 1e12 to convert to USD.
	 */
	function computeDollarValue(
		address _token,
		uint256 _amount
	) public view returns (uint256 dollarValue_) {
		uint256 decimals_ = vault.tokenDecimals(_token); // Get the decimals of the token using the Vault interface
		dollarValue_ = ((_amount * vault.getMinPrice(_token)) / 10 ** decimals_); // Calculate the dollar value by multiplying the amount by the current dollar value of the token on the vault and dividing by 10^decimals
		dollarValue_ = dollarValue_ / 1e12; // Convert the result to USD by dividing by 1e12
	}

	/**
	 * @dev Public function to get the current period index.
	 * @return periodIndex_ index of the day
	 */
	function getPeriodIndex() public view returns (uint256 periodIndex_) {
		periodIndex_ = (block.timestamp - periodStartTime) / 1 days;
	}

	function _setLastDayReserves() internal {
		// Get the length of the allWhitelistedTokens array
		uint256 allWhitelistedTokensLength_ = vault.allWhitelistedTokensLength();

		// Iterate over all whitelisted tokens in the vault
		for (uint256 i = 0; i < allWhitelistedTokensLength_; i++) {
			address token_ = vault.allWhitelistedTokens(i); // Get the address of the current token
			(uint256 loss_, uint256 profit_) = vault.returnTotalOutAndIn(token_);
			// Store the previous day's profit and loss for the current token
			lastDayReserves[token_] = LastDayReserves(profit_, loss_);
		}
	}

	/**
	 *
	 * @dev Calculates the change in dollar value of the vault's reserves and the last day's P&L.
	 * @return change_ The change in dollar value of the vault's reserves.
	 * @return lastDayPnl_ The last day's profit and loss.
	 */
	function _getChange() internal returns (int256 change_, int256 lastDayPnl_) {
		uint256 allWhitelistedTokensLength_ = vault.allWhitelistedTokensLength();

		// Create a LastDayReserves struct to store the previous day's reserve data
		LastDayReserves memory lastDayReserves_;

		// Iterate over all whitelisted tokens in the vault
		for (uint256 i = 0; i < allWhitelistedTokensLength_; i++) {
			address token_ = vault.allWhitelistedTokens(i); // Get the address of the current token
			// Get the previous day's profit and loss for the current token
			lastDayReserves_ = lastDayReserves[token_];
			// Calculate the previous day's profit and loss in USD
			uint256 lastDayProfit = computeDollarValue(
				token_,
				lastDayReserves[token_].profit
			);
			uint256 lastDayLoss = computeDollarValue(
				token_,
				lastDayReserves[token_].loss
			);
			// Add the previous day's profit and loss to the last day's P&L
			lastDayPnl_ += int256(lastDayProfit) - int256(lastDayLoss);
		}

		_setLastDayReserves();

		for (uint256 i = 0; i < allWhitelistedTokensLength_; i++) {
			address token_ = vault.allWhitelistedTokens(i); // Get the address of the current token
			// Calculate the current day's profit and loss in USD
			uint256 profit_ = lastDayReserves[token_].profit - lastDayReserves_.profit;
			uint256 loss_ = lastDayReserves[token_].loss - lastDayReserves_.loss;

			uint256 profitInDollar_ = computeDollarValue(token_, profit_);
			uint256 lossInDollar_ = computeDollarValue(token_, loss_);

			// Add the current day's profit and loss to the change in reserves
			change_ += int256(profitInDollar_) - int256(lossInDollar_);
		}
	}

	function _getMultiplier() internal returns (uint256) {
		// Get the current period index
		uint256 index_ = getPeriodIndex();

		// If the current period index is the same as the last calculated index, return the current multiplier
		// This is to prevent the multiplier from being calculated multiple times in the same period
		if (index_ == lastCalculatedIndex) {
			return currentMultiplier;
		}

		// Get the change in reserves and the last day's P&L
		(int256 change_, int256 lastDayPnl_) = _getChange();

		// If the current period index is 0 or 1, return the max multiplier
		if (index_ <= 1) {
			lastCalculatedIndex = index_;
			return config.maxMultiplier;
		}

		// If the last day's P&L is 0, return the current multiplier
		if (lastDayPnl_ == 0) {
			lastCalculatedIndex = index_;
			return currentMultiplier;
		}

		// Calculate the period change rate based on the change in reserves and the last day's P&L
		uint256 periodChangeRate_ = (absoluteValue(change_) * PRECISION) /
			absoluteValue(lastDayPnl_);

		// If the difference in reserves represents a loss, decrease the current multiplier accordingly
		if (change_ < 0) {
			uint256 decrease_ = (2 * (currentMultiplier * periodChangeRate_)) / PRECISION;
			currentMultiplier = currentMultiplier > decrease_
				? currentMultiplier - decrease_
				: config.minMultiplier;
		}
		// Otherwise, increase the current multiplier according to the period change rate
		else if (periodChangeRate_ != 0) {
			currentMultiplier =
				(currentMultiplier * (1e18 + periodChangeRate_)) /
				PRECISION;
		}

		// If the current multiplier exceeds the maximum multiplier value, set it to the maximum value
		currentMultiplier = currentMultiplier > config.maxMultiplier
			? config.maxMultiplier
			: currentMultiplier;

		// If the current multiplier is less than the minimum multiplier value, set it to the minimum value
		currentMultiplier = currentMultiplier < config.minMultiplier
			? config.minMultiplier
			: currentMultiplier;

		// Update the last calculated index to the current period index
		lastCalculatedIndex = index_;

		// Set the wager fee for the current period index and current multiplier
		_setWagerFee(currentMultiplier);

		// Return the current multiplier
		return currentMultiplier;
	}

	/**
	 * @param _token address of the input (wl) token
	 * @param _amount amount of the token
	 * @notice function to calculation with current multiplier
	 */
	function calculate(address _token, uint256 _amount) external returns (uint256 amount_) {
		uint256 value_ = computeDollarValue(_token, _amount);
		amount_ = (value_ * _getMultiplier()) / PRECISION;
	}

	/**
	 *
	 * @param _num The number to get the absolute value of
	 * @dev Returns the absolute value of a number
	 */
	function absoluteValue(int _num) public pure returns (uint) {
		if (_num < 0) {
			return uint(-1 * _num);
		} else {
			return uint(_num);
		}
	}
}

