// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "./IWINR.sol";
import "./IVault.sol";
import "./AccessControlBase.sol";
import "./IVault.sol";

contract MiningStrategy is AccessControlBase {
	/*==================================================== Events =============================================================*/

	event MiningMultiplierChanged(uint256 multiplier);
	event AddressesUpdated(IWINR token, IVault vault);
	event ConfigUpdated(uint256[] _percentages, Config[] _configs);
	event VolumeIncreased(uint256 _amount, uint256 _newVolume, uint256 _dayIndex);
	event VolumeDecreased(uint256 _amount, uint256 _newVolume, uint256 _dayIndex);
	event AccountMultiplierChanged(address _account, uint256 _newMultiplier);

	/*==================================================== State Variables ====================================================*/

	struct Config {
		uint256 minMultiplier;
		uint256 maxMultiplier;
	}

	IWINR public WINR;
	IVault public vault;
	///@notice address of the WINR pool
	address public pool;
	///@notice address of the WINR pair token in the pool
	IERC20 public pairToken;

	/// @notice max mint amount by games
	uint256 public immutable MAX_MINT;
	/// @notice Last parity of ETH/WINR
	uint256 public parity;
	/// @notice Last calculated multipliers index id
	uint256 public lastCalculatedIndex;
	/// @notice The volumes of given period duration
	mapping(uint256 => uint256) public dailyVolumes;
	/// @notice The volumes of given period duration
	mapping(uint256 => uint256) public dailyVolumeCurrentMultiplier;
	/// @notice Multipliers of accounts
	mapping(address => uint256) public accountMultipliers;
	/// @notice Last calculated multiplier
	uint256 public currentMultiplier;
	/// @notice Start time of periods
	uint256 public volumeRecordStartTime = block.timestamp - 2 days;

	uint256[] public percentages;
	mapping(uint256 => Config) public halvings;

	/*==================================================== Constant Variables ==================================================*/

	/// @notice used to calculate precise decimals
	uint256 private constant PRECISION = 1e18;

	/*==================================================== Configurations ===========================================================*/

	constructor(
		address _vaultRegistry,
		address _timelock,
		uint256 _maxMint
	) AccessControlBase(_vaultRegistry, _timelock) {
		MAX_MINT = _maxMint;
	}

	/**
	 *
	 * @dev Internal function to update the halvings mapping.
	 * @param _percentages An array of percentages at which the halvings will occur.
	 * @param _configs An array of configurations to be associated with each halving percentage.
	 * @notice The function requires that the lengths of the two input arrays must be equal.
	 * @notice Each configuration must have a non-zero value for both minMultiplier and maxMultiplier.
	 * @notice The minimum multiplier value must be less than the maximum multiplier value for each configuration.
	 * @notice For each percentage in the _percentages array, the corresponding configuration in the _configs array will be associated with the halvings mapping.
	 * @notice After the halvings are updated, the percentages and configurations arrays will be updated and a ConfigUpdated event will be emitted with the new arrays as inputs.
	 */
	function _updateHalvings(uint256[] memory _percentages, Config[] memory _configs) internal {
		require(_percentages.length == _configs.length, "Lengths must be equal");
		require(_percentages.length <= type(uint8).max, "Too many halvings");
		for (uint256 i = 0; i < _percentages.length; i++) {
			require(_configs[i].maxMultiplier != 0, "Max zero");
			require(_configs[i].minMultiplier != 0, "Min zero");
			require(
				_configs[i].minMultiplier < _configs[i].maxMultiplier,
				"Min greater than max"
			);
			halvings[_percentages[i]] = _configs[i];
		}
		percentages = _percentages;

		if (currentMultiplier == 0) {
			currentMultiplier = _configs[0].maxMultiplier;
		}

		emit ConfigUpdated(_percentages, _configs);
	}

	/**
	 *
	 * @param _percentages An array of percentages at which the halvings will occur.
	 * @param _configs  An array of configurations to be associated with each halving percentage.
	 * @dev Allows the governance role to update the halvings mapping.
	 */
	function updateHalvings(
		uint256[] memory _percentages,
		Config[] memory _configs
	) public onlyGovernance {
		_updateHalvings(_percentages, _configs);
	}

	/**
	 *
	 * @dev Allows the governance role to update the contract's addresses for the WINR token, Vault, Pool, and Pair Token.
	 * @param _WINR The new address of the WINR token contract.
	 * @param _vault The new address of the Vault contract.
	 * @param _pool The new address of the Pool contract.
	 * @param _pairToken The new address of the Pair Token contract.
	 * @notice Each input address must not be equal to the zero address.
	 * @notice The function updates the corresponding variables with the new addresses.
	 * @notice After the addresses are updated, the parity variable is updated by calling the getParity() function.
	 * @notice Finally, an AddressesUpdated event is emitted with the updated WINR and Vault addresses.
	 */
	function updateAddresses(
		IWINR _WINR,
		IVault _vault,
		address _pool,
		IERC20 _pairToken
	) public onlyGovernance {
		require(address(_WINR) != address(0), "WINR address zero");
		require(address(_vault) != address(0), "Vault zero");
		require(_pool != address(0), "Pool zero");
		require(address(_pairToken) != address(0), "Pair Token zero");
		WINR = _WINR;
		vault = _vault;
		pool = _pool;
		pairToken = _pairToken;
		parity = getParity();

		emit AddressesUpdated(_WINR, _vault);
	}

	function setAccountMultiplier(address _account, uint256 _multiplier) external onlySupport {
		accountMultipliers[_account] = _multiplier;

		emit AccountMultiplierChanged(_account, _multiplier);
	}

	/*==================================================== Volume ===========================================================*/

	function getVolumeDayIndex() public view returns (uint256 day_) {
		day_ = (block.timestamp - volumeRecordStartTime) / 1 days;
	}

	/**
    @dev Public function to get the daily volume of a specific day index.
    @param _dayIndex The index of the day for which to get the volume.
    @return volume_ The  volume of the specified day index.
    @notice This function takes a day index and returns the volume of that day,
    as stored in the dailyVolumes mapping.
    */
	function getVolumeOfDay(uint256 _dayIndex) public view returns (uint256 volume_) {
		volume_ = dailyVolumes[_dayIndex]; // Get the  volume of the specified day index from the dailyVolumes mapping
	}

	/**
    @dev Public function to calculate the dollar value of a given token amount.
    @param _token The address of the whitelisted token on the vault.
    @param _amount The amount of the given token.
    @return dollarValue_ The dollar value of the given token amount.
    @notice This function takes the address of a whitelisted token on the vault and an amount of that token,
    and calculates the dollar value of that amount by multiplying the amount by the current dollar value of the token
    on the vault and dividing by 10^decimals of the token. The result is then divided by 1e12 to convert to USD.
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
	 *
	 * @dev External function to increase the volume of the current day index.
	 * @dev This function is called by the Token Manager to increase the volume of the current day index.
	 * @param _input The address of the token to increase the volume.
	 * @param _amount The amount of the token to increase the volume.
	 * @notice This function is called by the Token Manager to increase the volume
	 *  of the current day index. It calculates the dollar value of the token amount using
	 *  the computeDollarValue function, adds it to the volume of the current day
	 *  index, and emits a VolumeIncreased event with the updated volume.
	 */
	function increaseVolume(address _input, uint256 _amount) external onlyProtocol {
		uint256 dayIndex_ = getVolumeDayIndex(); // Get the current day index to update the volume
		uint256 dollarValue_ = computeDollarValue(_input, _amount); // Calculate the dollar value of the token amount using the computeDollarValue function
		unchecked {
			dailyVolumes[dayIndex_] += dollarValue_; // Increase the volume of the current day index by the calculated dollar value
		}
		emit VolumeIncreased(dollarValue_, dailyVolumes[dayIndex_], dayIndex_); // Emit a VolumeIncreased event with the updated volume
	}

	/**
	 *
	 * @dev External function to decrease the volume of the current day index.
	 * @dev This function is called by the Token Manager to decrease the volume of the current day index.
	 * @param _input The address of the token to decrease the volume.
	 * @param _amount The amount of the token to decrease the volume.
	 * @notice This function is called by the Token Manager to decrease the volume
	 *  of the current day index. It calculates the dollar value of the token amount using
	 *  the computeDollarValue function, subtracts it from the  volume of the current day
	 *  index, and emits a VolumeDecreased event with the updated volume.
	 */
	function decreaseVolume(address _input, uint256 _amount) external onlyProtocol {
		uint256 dayIndex_ = getVolumeDayIndex(); // Get the current day index to update the  volume
		uint256 dollarValue_ = computeDollarValue(_input, _amount); // Calculate the dollar value of the token amount using the computeDollarValue function

		// Decrease the  volume of the current day index by the calculated dollar value
		if (dailyVolumes[dayIndex_] > dollarValue_) {
			dailyVolumes[dayIndex_] -= dollarValue_;
		} else {
			dailyVolumes[dayIndex_] = 0;
		}

		emit VolumeDecreased(dollarValue_, dailyVolumes[dayIndex_], dayIndex_); // Emit a VolumeDecreased event with the updated volume
	}

	/*================================================== Mining =================================================*/

	function getParity() public view returns (uint256 value_) {
		// calculates with the decimal of WINR and the decimal of pairToken
		value_ =
			(pairToken.balanceOf(pool) *
				(PRECISION / 10 ** vault.tokenDecimals(address(pairToken))) *
				PRECISION) /
			WINR.balanceOf(pool);
	}

	/**
	 * @notice This function calculates the mining multiplier based on the current day's volume and the previous day's volume
	 * @dev It takes in two parameters, the number of tokens minted by games and the maximum number of tokens that can be minted
	 * @dev It returns the current mining multiplier as an int256
	 * @dev _mintedByGames and MAX_MINT are using to halving calculation
	 * @param _mintedByGames The total minted Vested WINR amount
	 */
	function _getMultiplier(uint256 _mintedByGames) internal returns (uint256) {
		uint256 index_ = getVolumeDayIndex();

		// If the current day's index is the same as the last calculated index, return the current multiplier
		if (lastCalculatedIndex == index_) {
			return currentMultiplier;
		}

		// Get the current configuration based on the number of tokens minted by games and the maximum number of tokens that can be minted
		Config memory config_ = getCurrentConfig(_mintedByGames);

		// Get the volume of the previous day and the current day
		uint256 prevDayVolume_ = getVolumeOfDay(index_ - 2);
		uint256 currentDayVolume_ = getVolumeOfDay(index_ - 1);

		// If either the current day's volume or the previous day's volume is zero, return the current multiplier
		if (currentDayVolume_ == 0 || prevDayVolume_ == 0) {
			dailyVolumeCurrentMultiplier[index_] = currentMultiplier;
			return currentMultiplier;
		}

		// Calculate the percentage change in volume between the previous day and the current day
		uint256 diff_ = (
			currentDayVolume_ > prevDayVolume_
				? currentDayVolume_ - prevDayVolume_
				: prevDayVolume_ - currentDayVolume_
		);
		uint256 periodChangeRate_ = ((diff_ * 1e36) / prevDayVolume_) / PRECISION;

		// Calculate the new multiplier and ensure it's within the configured range
		uint256 newMultiplier;
		if (currentDayVolume_ < prevDayVolume_) {
			newMultiplier =
				(currentMultiplier * (1e18 + 2 * periodChangeRate_)) /
				PRECISION;
		} else {
			uint256 decrease = (currentMultiplier * periodChangeRate_) / PRECISION;
			newMultiplier = decrease > currentMultiplier
				? config_.minMultiplier
				: currentMultiplier - decrease;
		}
		newMultiplier = newMultiplier > config_.maxMultiplier
			? config_.maxMultiplier
			: newMultiplier;
		newMultiplier = newMultiplier < config_.minMultiplier
			? config_.minMultiplier
			: newMultiplier;

		// Set the new multiplier for the current day and emit an event
		currentMultiplier = newMultiplier;
		dailyVolumeCurrentMultiplier[index_] = currentMultiplier;
		emit MiningMultiplierChanged(currentMultiplier);

		// Update the last calculated index and return the current multiplier
		lastCalculatedIndex = index_;
		return currentMultiplier;
	}

	/**
	 *
	 * @param _account address of the account
	 * @param _amount amount of the token
	 * @param _mintedByGames minted Vested WINR amount
	 * @dev This function is called by the Token Manager to calculate the mint amount
	 * @notice This function calculates the mint amount based on the current day's volume and the previous day's volume
	 */
	function calculate(
		address _account,
		uint256 _amount,
		uint256 _mintedByGames
	) external returns (uint256 mintAmount_) {
		// If the account has a multiplier, use it to calculate the mint amount
		if (accountMultipliers[_account] != 0) {
			mintAmount_ = _calculate(_amount, accountMultipliers[_account]);
		} else {
			// Otherwise, use the current multiplier to calculate the mint amount
			mintAmount_ = _calculate(_amount, _getMultiplier(_mintedByGames));
		}
	}

	/**
	 * @notice This function calculates the mint amount based on the current day's volume and the previous day's volume
	 * @param _amount The amount of tokens to calculate the mint amount for
	 * @param _multiplier The multiplier to use to calculate the mint amount
	 */
	function _calculate(uint256 _amount, uint256 _multiplier) internal view returns (uint256) {
		return ((_amount * _multiplier * PRECISION) / parity) / PRECISION;
	}


	function getCurrentConfig(
		uint256 _mintedByGames
	) public view returns (Config memory config) {
		uint256 ratio_ = (PRECISION * _mintedByGames) / MAX_MINT;
		uint8 index_ = findIndex(ratio_);
		return halvings[percentages[index_]];
	}

	function findIndex(uint256 ratio) internal view returns (uint8 index) {
		uint8 min_ = 0;
		uint8 max_ = uint8(percentages.length) - 1;

		while (min_ < max_) {
			uint8 mid_ = (min_ + max_) / 2;
			if (ratio < percentages[mid_]) {
				max_ = mid_;
			} else {
				min_ = mid_ + 1;
			}
		}

		return min_;
	}
}

