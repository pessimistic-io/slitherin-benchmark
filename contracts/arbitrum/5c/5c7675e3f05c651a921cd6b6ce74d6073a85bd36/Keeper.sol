// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Math } from "./Math.sol";

import { IERC20TokenReceiver } from "./IERC20TokenReceiver.sol";

import { PausableAccessControl } from "./PausableAccessControl.sol";
import { TokenUtils } from "./TokenUtils.sol";
import "./Errors.sol";

/// @title Keeper
/// @author Koala Money
contract Keeper is IERC20TokenReceiver, PausableAccessControl, ReentrancyGuard {
	/// @notice Struct describing the user info
	struct UserInfo {
		///@notice Amount of synthethic tokens deposited, decreases when tokens are converted (convertedAmount increases).
		uint256 totalStaked;
		///@notice Amount of synthethic tokens that have been converted into native tokens and ready to claim as native tokens.
		uint256 totalConverted;
		///@notice Keep track of last time the dividends were updated for each user.
		uint256 lastDividendPoints;
		///@notice Last block number user interactived with the keeper.
		uint256 lastUserAction;
	}

	/// @notice The scalar used for conversion of integral numbers to fixed point numbers.
	uint256 public constant FIXED_POINT_SCALAR = 1e18;

	/// @notice The address of the synthetic token to convert to base token.
	address public immutable synthToken;

	/// @notice The address of the native token.
	address public immutable nativeToken;

	uint8 public immutable nativeTokenDecimals;

	uint8 public immutable synthTokenDecimals;

	/// @notice The length (in blocks) of one full distribution phase.
	uint256 public distributionPeriod;

	///@notice Total reserve of synth token staked by users.
	uint256 public totalStaked;

	/// @notice Total reserve of native token to share.
	uint256 public nativeTokenReserve;

	///@notice Beginning of last distribution cycle.
	uint256 public lastDistributionBlock;

	/// @notice Gives the id of the next added user.
	uint256 public nextUserId;

	/// @notice Checks if a user is known.
	mapping(address => bool) public isKnownUser;

	/// @notice Total amount of native tokens already converted.
	uint256 private _nativeTokenConvertedReserve;

	///@notice Sum of weights.
	uint256 private _totalDividendPoints;

	/// @notice Associates a unique id with a user address.
	mapping(uint256 => address) private _userList;

	/// @notice Associates user infos with user address.
	mapping(address => UserInfo) private _userInfos;

	constructor(
		address _synthToken,
		address _nativeToken,
		uint256 _distributionPeriod
	) {
		synthToken = _synthToken;
		nativeToken = _nativeToken;
		distributionPeriod = _distributionPeriod;

		nativeTokenDecimals = TokenUtils.expectDecimals(_nativeToken);
		synthTokenDecimals = TokenUtils.expectDecimals(_synthToken);
	}

	/// @notice Sets the distribution period.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	/// @notice Reverts with an {ZeroValue} error if the distribution period is 0.
	///
	/// @notice Emits a {DistributionPeriodUpdated} event.
	///
	/// @param _distributionPeriod The length (in block) of one full distribution phase.
	function setDistributionPeriod(uint256 _distributionPeriod) external {
		_onlyAdmin();
		if (_distributionPeriod == 0) {
			revert ZeroValue();
		}
		distributionPeriod = _distributionPeriod;

		emit DistributionPeriodUpdated(_distributionPeriod);
	}

	/// @notice Deposits synthetic tokens into the keeper in order to get the right to convert them into native tokens over time.
	///
	/// @notice Reverts with an {ContractPaused} error if the contract is in pause state.
	/// @notice Reverts with an {ZeroValue} error if the stake amount is 0.
	///
	/// @notice Emits a {TokensStaked} event.
	///
	/// @param _amount the amount of synthetic tokens to stake.
	function stake(uint256 _amount) external nonReentrant {
		_checkNotPaused();
		if (_amount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		// Adds user to known list to control liquidations
		_addUserToKnownList(msg.sender);

		// Transfers synthetic tokens from user to keeper
		TokenUtils.safeTransferFrom(synthToken, msg.sender, address(this), _amount);

		// Increases user stake amount
		_increaseStakeFor(msg.sender, _amount);

		emit TokensStaked(msg.sender, _amount);
	}

	/// @notice Withdraws staked synthetic tokens from the keeper.
	/// @notice User gives up the converted tokens when calling this function.
	///
	/// @notice Reverts with an {ContractPaused} error if the contract is in pause state.
	/// @notice Reverts with an {ZeroValue} error if the unstake amount is 0.
	///
	/// @notice Emits a {TokensUnstaked} event.
	///
	/// @param _amount The amount of synthetic tokens to unstake.
	function unstake(uint256 _amount) external nonReentrant {
		_checkNotPaused();
		_distribute();
		_update(msg.sender);

		// Claims native tokens
		_claim(msg.sender);

		// Computes effective unstake amount allowed for user
		uint256 _unstakeAmount = _getEffectiveUnstakeFor(msg.sender, _amount);

		_unstake(msg.sender, _unstakeAmount);
	}

	/// @notice Executes claim() on another account that has more converted tokens than synthethic tokens staked.
	/// @notice The caller of this function will have the surplus base tokens credited to their balance, rewarding them for performing this action.
	///
	/// @notice Reverts with an {LiquidationForbidden} if the address has nothing to liquidate.
	/// @notice Reverts with an {ContractPaused} error if the contract is in pause state.
	///
	/// @notice Emits a {TokensLiquidated} event.
	///
	/// @param _toLiquidate address of the account you will force convert.
	function liquidate(address _toLiquidate) external nonReentrant {
		_checkNotPaused();
		_distribute();
		_update(msg.sender);
		_update(_toLiquidate);

		// Calculates overflow for liquidated user
		uint256 _overflow = _getOverflowFor(_toLiquidate);

		// Checks if valid liquidation
		if (_overflow == 0) {
			revert LiquidationForbidden();
		}

		// Closes liquidated user position
		_claim(_toLiquidate);

		// Grants overflow to liquidator
		_increaseConvertedForLiquidator(msg.sender, _overflow);

		emit TokensLiquidated(msg.sender, _toLiquidate, _overflow);
	}

	/// @notice Allows user to forfeit converted tokens and withdraw all staked tokens.
	///
	/// @notice Reverts with an {NothingStaked} error if the unstake amount is 0.
	///
	/// @notice Emits a {EmergencyExitCompleted} event.
	function emergencyExit() external nonReentrant {
		_distribute();
		_update(msg.sender);
		// Computes effective debt reduction allowed for user
		uint256 _unstakeAmount = _getMaxUnstakeFor(msg.sender);
		if (_unstakeAmount == 0) {
			revert NothingStaked();
		}
		// Forfeits converted native tokens
		_resetConvertedFor(msg.sender);

		// Unstakes synthethic tokens
		_unstake(msg.sender, _unstakeAmount);

		emit EmergencyExitCompleted(msg.sender, _unstakeAmount);
	}

	/// @notice Checks the amount of vault token available and distributes it during the next phased period.
	function distribute() external nonReentrant {
		_distribute();
		_syncNativeTokenReserve();
	}

	///  IERC20TokenReceiver
	function onERC20Received(address _token, uint256 _amount) external nonReentrant {
		_distribute();
		_syncNativeTokenReserve();
	}

	/// @notice Gets the status of a user's staking position.
	///
	/// @param _user The address of the user to query.
	///
	/// @return The amount of tokens staked for user.
	/// @return The amount of synthetic tokens converted and ready to be claimed as native tokens.
	function userInfo(address _user) external view returns (uint256, uint256) {
		return _getUserInfoFor(_user);
	}

	/// @notice Gets the status of a a list of users.
	///
	/// @param _from The index of the first user to query (included).
	/// @param _to The index of the last user to query (excluded).
	///
	/// @return _addressList The addresses of the users.
	/// @return _stakedAmount The amount of tokens staked for users.
	/// @return _convertedAmount The amount of synthetic tokens converted and ready to be claimed as native tokens.
	function userInfos(uint256 _from, uint256 _to)
		external
		view
		returns (
			address[] memory, //addressList,
			uint256[] memory, //totalStakedList,
			uint256[] memory //totalConvertedList
		)
	{
		if (_to > nextUserId || _from >= _to) {
			revert OutOfBoundsArgument();
		}

		uint256 _delta = _to - _from;
		address[] memory _addressList = new address[](_delta);
		uint256[] memory _totalStakedList = new uint256[](_delta);
		uint256[] memory _totalConvertedList = new uint256[](_delta);

		for (uint256 i = 0; i < _delta; ++i) {
			address _user = _userList[_from + i];
			_addressList[i] = _user;
			(_totalStakedList[i], _totalConvertedList[i]) = _getUserInfoFor(_user);
		}
		return (_addressList, _totalStakedList, _totalConvertedList);
	}

	/// @notice Gets the total amount to distribute to users.
	///
	/// @return The total amount of native tokens to distribute during distribution period.
	function getNativeTokenToDistribute() external view returns (uint256) {
		return _getNativeTokenToDistribute();
	}

	/// @notice Allows `_owner` to claim its converted native tokens.
	///
	/// @param _owner The address of the account to claim converted native tokens for.
	function _claim(address _owner) internal {
		// Gets claimable amount
		uint256 _claimableAmount = _getClaimableFor(_owner);

		if (_claimableAmount > 0) {
			// Resets converted amount
			_resetConvertedFor(_owner);
			// Decreases user stake and burns synth tokens
			_decreaseStakeFor(_owner, _claimableAmount);
			TokenUtils.safeBurn(synthToken, _claimableAmount);
			// Transfers converted tokens to user
			nativeTokenReserve -= _claimableAmount;
			TokenUtils.safeTransfer(nativeToken, _owner, _claimableAmount);
		}

		emit TokensClaimed(_owner, _claimableAmount);
	}

	/// @notice Allows `_owner` to unstake its synthethic tokens.
	///
	/// @param _owner The address of the account to claim converted native tokens for.
	/// @param _amount The amount of tokens to unstake
	function _unstake(address _owner, uint256 _amount) internal {
		if (_amount > 0) {
			_decreaseStakeFor(_owner, _amount);

			TokenUtils.safeTransfer(synthToken, _owner, _amount);
		}

		emit TokensUnstaked(_owner, _amount);
	}

	function _normaliseSynthToNative(uint256 _amount) internal view returns (uint256) {
		return (_amount * (10**nativeTokenDecimals)) / 10**synthTokenDecimals;
	}

	function _normaliseNativeToSynth(uint256 _amount) internal view returns (uint256) {
		return (_amount * (10**synthTokenDecimals)) / 10**nativeTokenDecimals;
	}

	/// @notice Increases distributed amount for user `_owner`.
	///
	/// @param _owner The address of the account to update the totalconverted amount for.
	function _update(address _owner) internal {
		UserInfo storage _userInfo = _userInfos[_owner];
		uint256 _extraConverted = (_userInfo.totalStaked * (_totalDividendPoints - _userInfo.lastDividendPoints)) /
			FIXED_POINT_SCALAR;

		_userInfo.totalConverted += _extraConverted;
		_userInfo.lastDividendPoints = _totalDividendPoints;
	}

	/// @notice Synchronises native token known balance with effective balance.
	function _syncNativeTokenReserve() internal {
		nativeTokenReserve = TokenUtils.safeBalanceOf(nativeToken, address(this));
	}

	/// @notice Run the phased distribution of the funds
	function _distribute() internal {
		uint256 _totalStaked = totalStaked;
		if (_totalStaked > 0) {
			uint256 _toDistribute = _getNativeTokenToDistribute();
			if (_toDistribute > 0) {
				_nativeTokenConvertedReserve += _toDistribute;
				_totalDividendPoints += (_toDistribute * FIXED_POINT_SCALAR) / _totalStaked;
			}
		}
		lastDistributionBlock = block.number;
	}

	/// @notice Increases the amount of synth token staked for `_owner` by `_amount`
	///
	/// @param _owner The address of the account to increase stake for.
	/// @param _amount The additional amount of synth tokens staked.
	function _increaseStakeFor(address _owner, uint256 _amount) internal {
		UserInfo storage _userInfo = _userInfos[_owner];
		_userInfo.totalStaked += _amount;
		totalStaked += _amount;
	}

	/// @notice Decreases the amount of synth token staked for `_owner` by `_amount`.
	///
	/// @param _owner The address of the account to decrease stake for.
	/// @param _amount The reduced amount of synth tokens staked.
	function _decreaseStakeFor(address _owner, uint256 _amount) internal {
		UserInfo storage _userInfo = _userInfos[_owner];
		_userInfo.totalStaked -= _amount;
		totalStaked -= _amount;
	}

	/// @notice Converted tokens are forfeited by `_owner`.
	///
	/// @param _owner The address of the account to forfeit rewards for.
	function _resetConvertedFor(address _owner) internal {
		UserInfo storage _userInfo = _userInfos[_owner];
		_nativeTokenConvertedReserve -= _userInfo.totalConverted;
		_userInfo.totalConverted = 0;
	}

	/// @notice Increases converted position for the liquidator.
	/// @notice This function is called when a user is liquidated.
	///
	/// @param _liquidator The address of the account that performs the liquidation.
	/// @param _overflow The amount of native tokens to add to the converted position of the liquidator.
	function _increaseConvertedForLiquidator(address _liquidator, uint256 _overflow) internal {
		UserInfo storage _liquidatorInfo = _userInfos[_liquidator];
		_liquidatorInfo.totalConverted += _overflow;
		_nativeTokenConvertedReserve += _overflow;
	}

	/// @notice Adds `_user` to the list of known users
	///
	/// @param _user The address of the account to add to the list of known users.
	function _addUserToKnownList(address _user) internal {
		if (!isKnownUser[_user]) {
			isKnownUser[_user] = true;
			uint256 _id = nextUserId;
			_userList[_id] = _user;
			nextUserId = _id + 1;
		}
	}

	/// @notice Gets the status of a user's staking position.
	///
	/// @param _user The address of the user to query.
	///
	/// @return The amount of tokens staked for user.
	/// @return The amount of synthetic tokens converted and ready to be claimed as native tokens.
	function _getUserInfoFor(address _user) internal view returns (uint256, uint256) {
		UserInfo storage _userInfo = _userInfos[_user];

		uint256 _userTotalStaked = _userInfo.totalStaked;
		uint256 _userTotalConverted = _userInfo.totalConverted;

		// Rewards from last distribution
		_userTotalConverted +=
			(_userTotalStaked * (_totalDividendPoints - _userInfo.lastDividendPoints)) /
			FIXED_POINT_SCALAR;

		// Rewards from next distribution
		uint256 _totalStaked = totalStaked;
		if (_totalStaked != 0) {
			uint256 _toDistribute = _getNativeTokenToDistribute();
			_userTotalConverted += (_toDistribute * _userTotalStaked) / _totalStaked;
		}
		return (_userTotalStaked, _userTotalConverted);
	}

	/// @notice Gets the total amount to distribute to users.
	///
	/// @return The total amount of native tokens to distribute during distribution period.
	function _getNativeTokenToDistribute() internal view returns (uint256) {
		uint256 _distributionPeriod = distributionPeriod;
		uint256 _deltaBlocks = Math.min(block.number - lastDistributionBlock, _distributionPeriod);
		uint256 _nativeTokenAvailable = nativeTokenReserve - _nativeTokenConvertedReserve;
		uint256 _toDistribute = (_nativeTokenAvailable * _deltaBlocks) / _distributionPeriod;
		return _toDistribute;
	}

	/// @notice Gets the amount of converted tokens claimable by `_owner`.
	///
	/// @param _owner The address of the account to get the claimable amount for.
	///
	/// @return The amount of converted tokens claimable.
	function _getClaimableFor(address _owner) internal view returns (uint256) {
		UserInfo storage _userInfo = _userInfos[_owner];
		uint256 _claimableAmount = Math.min(_userInfo.totalConverted, _userInfo.totalStaked);

		return _claimableAmount;
	}

	/// @notice Gets the max stake reduction for `_owner`.
	///
	/// @param _owner The address of the account that wants to reduce its stake.
	///
	/// @return The max amount of unstaked tokens.
	function _getMaxUnstakeFor(address _owner) internal view returns (uint256) {
		UserInfo storage _userInfo = _userInfos[_owner];
		return _userInfo.totalStaked;
	}

	/// @notice Gets the effective stake reduction for `_owner`.
	///
	/// @param _owner The address of the account that wants to reduce its stake.
	/// @param _wishedUnstakedAmount The wished amount of tokens to unstake.
	///
	/// @return The effective amount of unstaked tokens.
	function _getEffectiveUnstakeFor(address _owner, uint256 _wishedUnstakedAmount) internal view returns (uint256) {
		UserInfo storage _userInfo = _userInfos[_owner];
		uint256 _effectiveUnstakedAmount = Math.min(_wishedUnstakedAmount, _userInfo.totalStaked);
		return _effectiveUnstakedAmount;
	}

	/// @notice Gets the overflow for `_owner`.
	/// @notice The overflow is the surplus between the amount of native tokens converted and the amount of synthethic tokens staked by `_owner`.
	/// @notice Returns 0 if there is no overflow.
	///
	/// @param _owner The address of the account to compute overflow for.
	///
	/// @return The overflow.
	function _getOverflowFor(address _owner) internal view returns (uint256) {
		UserInfo storage _liquidatedInfo = _userInfos[_owner];
		uint256 _liquidatedTotalStaked = _liquidatedInfo.totalStaked;
		uint256 _liquidatedTotalConverted = _liquidatedInfo.totalConverted;
		// If no overflow returns 0
		if (_liquidatedTotalStaked >= _liquidatedTotalConverted) {
			return 0;
		}
		uint256 _overflow = _liquidatedTotalConverted - _liquidatedTotalStaked;
		return _overflow;
	}

	/// @notice Emitted when `_user` stakes `amount` synthetic assets.
	///
	/// @param user The address of the user.
	/// @param amount The amount of synthetic tokens staked.
	event TokensStaked(address indexed user, uint256 amount);

	/// @notice Emitted when `_user` unstakes `amount` synthetic assets.
	///
	/// @param user The address of the user.
	/// @param amount The amount of synthetic tokens unstaked.
	event TokensUnstaked(address indexed user, uint256 amount);

	/// @notice Emitted when `user` claims `amount` of native tokens.
	///
	/// @param  user The address of the user.
	/// @param amount The amount of native tokens claimed.
	event TokensClaimed(address indexed user, uint256 amount);

	/// @notice Emitted when `user` liquidates `amount` synthetic assets from `toLiquidate`.
	///
	/// @param user The address of the user.
	/// @param toLiquidate The address of the user to liquidate.
	/// @param amount The amount of tokens liquidates.
	event TokensLiquidated(address indexed user, address toLiquidate, uint256 amount);

	/// @notice Emitted when `amount` of native tokens are received by the keeper.
	///
	/// @param amount The amount of native tokens received by the keeper.
	event NativeTokenReceived(uint256 amount);

	/// @notice Emitted when the distribution period is updated.
	///
	/// @param distributionPeriod The distribution period.
	event DistributionPeriodUpdated(uint256 distributionPeriod);

	/// @notice Emitted when the vault manager is migrated.
	///
	/// @param migrateTo The address of the new vault manager.
	/// @param totalFunds The total amount of funds migrated.
	event MigrationCompleted(address migrateTo, uint256 totalFunds);

	/// @notice Emitted when a user perform an emergency exit after a migration.
	///
	/// @param user The address of the user.
	/// @param amount The total amount of synthetic tokens unstaked.
	event EmergencyExitCompleted(address indexed user, uint256 amount);

	/// @notice Indicates that the unstake operation failed because user has nothing staked.
	error NothingStaked();

	/// @notice Indicates that the liquidation operation failed because liquidated user ready to convert balance has not overflown.
	error LiquidationForbidden();
}

