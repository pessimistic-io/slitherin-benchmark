// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import { IOracle } from "./IOracle.sol";
import { IWhitelist } from "./IWhitelist.sol";
import { IZooMinimal } from "./IZooMinimal.sol";
import { IERC20StakerMinimal } from "./IERC20StakerMinimal.sol";

import { AdminAccessControl } from "./AdminAccessControl.sol";
import { Sets } from "./Sets.sol";
import "./Errors.sol";

contract Controller is AdminAccessControl, ReentrancyGuard {
	/// @notice A structure to store the informations related to an account.
	struct UserInfo {
		/// @notice The set of staked tokens.
		Sets.AddressSet stakings;
		/// @notice The balance for each staked token.
		mapping(address => uint256) stakes;
		/// @notice Last block number a deposit was made.
		uint256 lastDeposit;
	}

	/// @notice A structure to store the informations related to a staking contract.
	struct StakeTokenParam {
		// Gives the multiplier associated with staking amount to compute user staking bonus.
		uint256 multiplier;
		// A flag to indicate if the staking is enabled.
		bool enabled;
	}

	/// @notice The scalar used for conversion of integral numbers to fixed point numbers. Fixed point numbers in this implementation have 18 decimals of resolution, meaning that 1 is represented as 1e18, 0.5 is represented as 5e17, and 2 is represented as 2e18.
	uint256 public constant FIXED_POINT_SCALAR = 1e18;

	/// @notice The minimum value that the collateralization limit can be set to by the admin. This is a safety rail to prevent the collateralization from being set to a value which breaks the system.
	/// This value is equal to 100%.
	uint256 public constant MINIMUM_COLLATERALIZATION = 1e18;

	/// @notice The minimum collateralization ratio allowed. Calculated as user deposit / user debt.
	uint256 public minimumSafeGuardCollateralization;

	/// @notice The minimum adjusted collateralization ratio. Calculates as (user deposit + user staking bonus) / user debt.
	uint256 public minimumAdjustedCollateralization;

	/// @notice The address of the contract which will manage the whitelisted contracts with access to the actions.
	address public whitelist;

	address public oracle;

	/// @notice The address of the zoo contract which will manage the deposit/withdraw/mint/burn actions.
	address public zoo;

	/// @notice The list of supported tokens to stake. Staked tokens are eligible for collateral ratio boost.
	Sets.AddressSet private _supportedStaking;

	/// @notice A mapping between a stake token address and the associated stake token parameters.
	mapping(address => StakeTokenParam) private _stakings;

	/// @notice A mapping of all of the user CDPs. If a user wishes to have multiple CDPs they will have to either
	/// create a new address or set up a proxy contract that interfaces with this contract.
	mapping(address => UserInfo) private _userInfos;

	constructor(uint256 _minimumSafeGuardCollateralization, uint256 _minimumAdjustedCollateralization) {
		minimumSafeGuardCollateralization = _minimumSafeGuardCollateralization;
		minimumAdjustedCollateralization = _minimumAdjustedCollateralization;
	}

	/// @notice Sets the address of the zoo.
	/// @notice The zoo allows user to deposit native token and borrow debt token.
	///
	/// @notice Reverts if the caller does not have the admin role.
	///
	/// @param _zoo The address of the new zoo.
	function setZoo(address _zoo) external {
		_onlyAdmin();
		if (_zoo == address(0)) {
			revert ZeroAddress();
		}

		zoo = _zoo;

		emit ZooUpdated(_zoo);
	}

	/// @notice Sets the address of the whitelist contract.
	/// @notice The whitelist controls the smartcontracts that can call the action methods.
	///
	/// @notice Reverts if the caller does not have the admin role.
	///
	/// @param _whitelist The address of the new whitelist.
	function setWhitelist(address _whitelist) external {
		_onlyAdmin();
		if (_whitelist == address(0)) {
			revert ZeroAddress();
		}

		whitelist = _whitelist;

		emit WhitelistUpdated(_whitelist);
	}

	function setOracle(address _oracle) external {
		_onlyAdmin();
		if (_oracle == address(0)) {
			revert ZeroAddress();
		}

		oracle = _oracle;

		emit OracleUpdated(_oracle);
	}

	/// @notice Sets the minimumSafeGuardCollateralization.
	/// @notice The minimumSafeGuardCollateralization is used to control if a user position is healthy. The deposit balance / debt balance of a user must be greater than the minimumSafeGuardCollateralization.
	///
	/// @notice Reverts if the collateralization limit is under 100%.
	/// @notice Reverts if the caller does not have the admin role.
	///
	/// @param _minimumSafeGuardCollateralization The new minimumSafeGuardCollateralization.
	function setMinimumSafeGuardCollateralization(uint256 _minimumSafeGuardCollateralization) external {
		_onlyAdmin();
		if (_minimumSafeGuardCollateralization < MINIMUM_COLLATERALIZATION) {
			revert MinimumCollateralizationBreached();
		}

		minimumSafeGuardCollateralization = _minimumSafeGuardCollateralization;

		emit MinimumSafeGuardCollateralizationUpdated(_minimumSafeGuardCollateralization);
	}

	/// @notice Sets the minimumAdjustedCollateralization.
	/// @notice The minimumAdjustedCollateralization is used to control if a user position is healthy. The (deposit balance + stake bonus) / debt balance of a user must be greater than the minimumSafeGuardCollateralization.
	///
	/// @notice Reverts if the collateralization limit is under 100%.
	/// @notice Reverts if the caller does not have the admin role.
	///
	/// @param _minimumAdjustedCollateralization The new minimumAdjustedCollateralization.
	function setMinimumAdjustedCollateralization(uint256 _minimumAdjustedCollateralization) external {
		_onlyAdmin();
		if (_minimumAdjustedCollateralization < MINIMUM_COLLATERALIZATION) {
			revert MinimumCollateralizationBreached();
		}

		minimumAdjustedCollateralization = _minimumAdjustedCollateralization;

		emit MinimumAdjustedCollateralizationUpdated(_minimumAdjustedCollateralization);
	}

	/// @notice Adds `_staker` to the set of staker contracts with a multiplier of `_multiplier`.
	///
	/// @notice Reverts if `_staker` is already in the set of staker.
	/// @notice Reverts if the caller does not have the admin role.
	///
	/// @param _staking The address of the staking contract.
	/// @param _multiplier the multiplier associated with the staking contract.
	function addSupportedStaking(address _staking, uint256 _multiplier) external {
		_onlyAdmin();
		_checkNotDuplicatedStaking(_staking);

		_stakings[_staking] = StakeTokenParam({ multiplier: _multiplier, enabled: false });

		Sets.add(_supportedStaking, _staking);

		emit StakingAdded(_staking);
		emit StakingMultiplierUpdated(_staking, _multiplier);
		emit StakingEnableUpdated(_staking, false);
	}

	/// @notice Sets the multiplier of `_staking` to `_multiplier`.
	///
	/// @notice Reverts if `_staking` is not a supported stake token.
	/// @notice Reverts if the caller does not have the admin role.
	///
	/// @param _staking The address of the token.
	/// @param _multiplier The value of the multiplier associated with the staking token.
	function setStakingMultiplier(address _staking, uint256 _multiplier) external {
		_onlyAdmin();
		_checkSupportedStaking(_staking);

		_stakings[_staking].multiplier = _multiplier;

		emit StakingMultiplierUpdated(_staking, _multiplier);
	}

	/// @notice Sets the status of `_staking` to `_enabled`.
	/// @notice Users can stake tokens into the zoo to increase the amount of debt token they can borrow.
	///
	/// @notice Reverts if `_staking` is not a supported stake token.
	/// @notice Reverts if the caller does not have the admin role.
	///
	/// @param _staking The address of the token
	/// @param _enabled True if `_staker` is added to the set of staked tokens.
	function setStakingEnabled(address _staking, bool _enabled) external {
		_onlyAdmin();
		_checkSupportedStaking(_staking);

		_stakings[_staking].enabled = _enabled;

		emit StakingEnableUpdated(_staking, _enabled);
	}

	/// @notice Allows to perform control before a deposit action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _zoo The address of the contract where the deposit action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The requested deposit amount.
	function controlBeforeDeposit(
		address _zoo,
		address _owner,
		uint256 _amount
	) external {
		_onlyZoo();
		_onlyWhitelisted(_owner);
	}

	/// @notice Allows to perform control before a withdraw action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _zoo The address of the contract where the withdraw action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The requested withdraw amount.
	function controlBeforeWithdraw(
		address _zoo,
		address _owner,
		uint256 _amount
	) external {
		_onlyZoo();
		_onlyWhitelisted(_owner);
		_checkDepositSameBlock(_owner);
	}

	/// @notice Allows to perform control before a mint action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _zoo The address of the contract where the mint action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The requested mint amount.
	function controlBeforeMint(
		address _zoo,
		address _owner,
		uint256 _amount
	) external {
		_onlyZoo();
		_onlyWhitelisted(_owner);
	}

	/// @notice Allows to perform control before a burn action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _zoo The address of the contract where the burn action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The requested burn amount.
	function controlBeforeBurn(
		address _zoo,
		address _owner,
		uint256 _amount
	) external {
		_onlyZoo();
		_onlyWhitelisted(_owner);
	}

	/// @notice Allows to perform control before a liquidate action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _zoo The address of the contract where the liquidate action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The requested liquidate amount.
	function controlBeforeLiquidate(
		address _zoo,
		address _owner,
		uint256 _amount
	) external {
		_onlyZoo();
		_onlyWhitelisted(_owner);
	}

	/// @notice Allows to perform control after a deposit action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _zoo The address of the contract where the deposit action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The deposited amount.
	function controlAfterDeposit(
		address _zoo,
		address _owner,
		uint256 _amount
	) external {
		_onlyZoo();

		_updateLastDeposit(_owner);
	}

	/// @notice Allows to perform control after a withdraw action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _zoo The address of the contract where the withdraw action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The withdrawn amount.
	function controlAfterWithdraw(
		address _zoo,
		address _owner,
		uint256 _amount
	) external {
		_onlyZoo();
		_validate(_owner);
	}

	/// @notice Allows to perform control after a mint action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _zoo The address of the contract where the mint action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The minted amount.
	function controlAfterMint(
		address _zoo,
		address _owner,
		uint256 _amount
	) external {
		_onlyZoo();
		_validate(_owner);
	}

	/// @notice Allows to perform control after a burn action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _zoo The address of the contract where the burn action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The burned amount.
	function controlAfterBurn(
		address _zoo,
		address _owner,
		uint256 _amount
	) external {
		_onlyZoo();
	}

	/// @notice Allows to perform control after a liquidate action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _zoo The address of the contract where the liquidate action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The liquidated amount.
	function controlAfterLiquidate(
		address _zoo,
		address _owner,
		uint256 _amount
	) external {
		_onlyZoo();
	}

	/// @notice Allows to perform control after a stake action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _staking The address of the contract where the stake action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The requested stake amount.
	function controlBeforeStake(
		address _staking,
		address _owner,
		uint256 _amount
	) external {
		_onlyStakingContract();
		_onlyWhitelisted(_owner);
		_checkEnabledStaking(_staking);
	}

	/// @notice Allows to perform control after an unstake action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _staking The address of the contract where the unstake action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The requested unstake amount.
	function controlBeforeUnstake(
		address _staking,
		address _owner,
		uint256 _amount
	) external {
		_onlyStakingContract();
		_onlyWhitelisted(_owner);
	}

	/// @notice Allows to perform control after a stake action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _staking The address of the contract where the stake action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The staked amount.
	function controlAfterStake(
		address _staking,
		address _owner,
		uint256 _amount
	) external {
		_onlyStakingContract();

		_addStakeToken(_staking, _owner);
	}

	/// @notice Allows to perform control after an unstake action.
	///
	/// @notice Reverts if the action is not allowed.
	///
	/// @param _staking The address of the contract where the unstake action is performed.
	/// @param _owner The address of the user that performs the action.
	/// @param _amount The unstaked amount.
	function controlAfterUnstake(
		address _staking,
		address _owner,
		uint256 _amount
	) external {
		_onlyStakingContract();

		IZooMinimal(zoo).sync(_owner);
		_validate(_owner);

		_removeStakeTokenIfNoBalance(_staking, _owner);
	}

	/// @notice Gets the list of staked tokens by `_owner`.
	///
	/// @param _owner The address of the user to query the staked tokens for.
	function getStakingsFor(address _owner) external view returns (address[] memory) {
		return _userInfos[_owner].stakings.values;
	}

	/// @notice Gets the list of supported staked tokens.
	function getSupportedStakings() external view returns (address[] memory) {
		return _supportedStaking.values;
	}

	/// @notice Checks if a token is available for staking.
	///
	/// @return true if the token can be staked.
	function isSupportedStaking(address _staking) external view returns (bool) {
		return Sets.contains(_supportedStaking, _staking);
	}

	/// @notice Gets the parameters associated with a stake token.
	///
	/// @param _staking The address of the stake token to query.
	///
	/// @return The parameters of the stake token.
	function getStakingParam(address _staking) external view returns (StakeTokenParam memory) {
		return _stakings[_staking];
	}

	/// @notice Gets the staking bonus for user `_owner`.
	///
	/// @param _owner The address of the user to compute the staking bonus for.
	///
	/// @return The staking bonus.
	function getStakingBonusFor(address _owner) external view returns (uint256) {
		return _getStakingBonusFor(_owner);
	}

	/// @notice Validates that a user position is healthy.
	/// @notice A position is never healthy if deposit / debt ratio is under collateralization.
	/// @notice Else, a position is healthy if deposit / debt ratio is above adjusted collateralization.
	/// @notice Else, a position is healthy if (deposit + stake bonus) / debt ratio is above adjusted collateralization.
	///
	/// @notice Reverts if the position is not healthy.
	///
	/// @param _owner The address of the user to check the health of the position for.
	function _validate(address _owner) internal view {
		(uint256 _deposit, int256 _debt) = IZooMinimal(zoo).userInfo(_owner);

		// If no debt the position is valid
		if (_debt <= 0) {
			return;
		}

		uint256 _price = IOracle(oracle).getPrice();

		// Checks direct debt factor
		uint256 _rawCollateralization = (_deposit * _price * FIXED_POINT_SCALAR) / uint256(_debt);

		if (_rawCollateralization < minimumSafeGuardCollateralization) {
			revert SafeGuardCollateralizationBreached();
		}
		// No needs to check staking bonus if deposit is enough
		if (_rawCollateralization >= minimumAdjustedCollateralization) {
			return;
		}
		// Check debt factor adjusted with staking
		uint256 _bonusFromStaking = _getStakingBonusFor(_owner);

		uint256 _adjustedCollateralization = ((_deposit * _price + _bonusFromStaking) * FIXED_POINT_SCALAR) /
			uint256(_debt);
		uint256 _minimumAdjustedCollateralization = minimumAdjustedCollateralization;
		if (_adjustedCollateralization < _minimumAdjustedCollateralization) {
			revert AdjustedCollateralizationBreached();
		}
	}

	/// @notice Calculates the user bonus from staking.
	/// @notice The bonus from staking increases the maximum debt allowed for a user.
	///
	/// @param _owner The address of the account to calculate the staking bonus for.
	function _getStakingBonusFor(address _owner) internal view returns (uint256) {
		uint256 _score = 0;

		address[] memory _stakingTokenList = _userInfos[_owner].stakings.values;
		for (uint256 i = 0; i < _stakingTokenList.length; ++i) {
			StakeTokenParam storage _param = _stakings[_stakingTokenList[i]];
			if (_param.enabled) {
				// Get user lock amount
				_score +=
					(IERC20StakerMinimal(_stakingTokenList[i]).balanceOf(_owner) * _param.multiplier) /
					FIXED_POINT_SCALAR;
			}
		}
		return _score;
	}

	/// @notice Adds `_staking` to the set of stake contract from `_owner`.
	///
	/// @param _staking The address of the stake contract.
	/// @param _owner The address of the user.
	function _addStakeToken(address _staking, address _owner) internal {
		Sets.add(_userInfos[_owner].stakings, _staking);
	}

	/// @notice Removes `_staking` from the set of stake contract from `_owner` if his/her balance is 0.
	///
	/// @param _staking The address of the stake contract.
	/// @param _owner The address of the user.
	function _removeStakeTokenIfNoBalance(address _staking, address _owner) internal {
		if (IERC20StakerMinimal(_staking).balanceOf(_owner) == 0) {
			Sets.remove(_userInfos[_owner].stakings, _staking);
		}
	}

	/// @notice Keeps track of last block a deposit was done by `_owner`.
	/// @notice Used to forbid deposit and withdraw in the same block to perform flashloan.
	///
	/// @param _owner The address of the user that performed a deposit operation.
	function _updateLastDeposit(address _owner) internal {
		_userInfos[_owner].lastDeposit = block.number;
	}

	/// @notice Checks if `_owner` has done a deposit operation in the current block.
	/// @notice Used to forbid deposit and withdraw in the same block to perform flashloan.
	///
	/// @notice Reverts if the last deposit from `_owner` occurred in the current block.
	///
	/// @param _owner The address of the owner to check the last deposit block number for.
	function _checkDepositSameBlock(address _owner) internal view {
		UserInfo storage _userInfo = _userInfos[_owner];
		if (block.number <= _userInfo.lastDeposit) {
			revert DepositSameBlock();
		}
	}

	/// @notice Checks if `_staking` is not an already existing staking token.
	///
	/// @notice Reverts if `_staking` already exists.
	function _checkNotDuplicatedStaking(address _staking) internal view {
		if (Sets.contains(_supportedStaking, _staking)) {
			revert DuplicatedStakingContract(_staking);
		}
	}

	/// @notice Checks if `_staking` is a supported staked token.
	///
	/// @notice Reverts if `_staking` is not supported.
	function _checkSupportedStaking(address _staking) internal view {
		if (!Sets.contains(_supportedStaking, _staking)) {
			revert UnsupportedStakingContract(_staking);
		}
	}

	/// @notice Checks if staking is enabled for `_staking`.
	///
	/// @notice Reverts if staking is disabled.
	function _checkEnabledStaking(address _staking) internal view {
		if (!_stakings[_staking].enabled) {
			revert DisabledStakingContract(_staking);
		}
	}

	/// @notice Checks the whitelist for msg.sender.
	///
	/// @notice Reverts if msg.sender is not in the whitelist.
	function _onlyWhitelisted(address _msgSender) internal view {
		// Checks if the message sender is an EOA. In the future, this potentially may break. It is important that functions
		// which rely on the whitelist not be explicitly vulnerable in the situation where this no longer holds true.
		if (tx.origin == _msgSender) {
			return;
		}

		// Only check the whitelist for calls from contracts.
		if (!IWhitelist(whitelist).isWhitelisted(_msgSender)) {
			revert OnlyWhitelistAllowed();
		}
	}

	/// @notice Check that the caller is a staking contract.
	function _onlyStakingContract() internal view {
		if (!Sets.contains(_supportedStaking, msg.sender)) {
			revert OnlyStakingContractAllowed();
		}
	}

	/// @notice Check that the caller is the zoo contract.
	function _onlyZoo() internal view {
		if (zoo != msg.sender) {
			revert OnlyZooAllowed();
		}
	}

	/// @notice Emitted when the minimumSafeGuardCollateralization is updated.
	///
	/// @param _minimumSafeGuardCollateralization The new minimumSafeGuardCollateralization.
	event MinimumSafeGuardCollateralizationUpdated(uint256 _minimumSafeGuardCollateralization);

	/// @notice Emitted when the minimumAdjustedCollateralization is updated.
	///
	/// @param _minimumAdjustedCollateralization The new minimumAdjustedCollateralization.
	event MinimumAdjustedCollateralizationUpdated(uint256 _minimumAdjustedCollateralization);

	/// @notice Emitted when `staker` is add to the set of staked tokens
	///
	/// @param staker The address of the added staker
	event StakingAdded(address staker);

	/// @notice Emitted when the stake token adapter is updated.
	///
	/// @param enabled The address of the adapter.
	event StakingEnableUpdated(address staker, bool enabled);

	/// @notice Emitted when the stake token multiplier is updated.
	///
	/// @param multiplier The value of the multiplier.
	event StakingMultiplierUpdated(address staker, uint256 multiplier);

	/// @notice Emitted when the address of the whitelist is updated.
	///
	/// @param whitelist The address of the whitelist.
	event WhitelistUpdated(address whitelist);

	/// @notice Emitted when the address of the zoo is updated.
	///
	/// @param zoo The address of the zoo.
	event ZooUpdated(address zoo);

	/// @notice Emitted when the address of the oracle is updated.
	///
	/// @param oracle The address of the oracle.
	event OracleUpdated(address oracle);

	/// @notice Indicates that an unlock operation failed because it puts the debt factor of the user below the authorized safe guard collateralization limit .
	error SafeGuardCollateralizationBreached();

	/// @notice Indicates that an unlock operation failed because it puts the debt factor of the user below the authorized adjusted collateralization limit.
	error AdjustedCollateralizationBreached();

	/// @notice Indicates that a token is not part of the allowed set of staking contracts.
	///
	/// @param stakeToken The address of the unsupported staking contract.
	error UnsupportedStakingContract(address stakeToken);

	/// @notice Indicates that a token is already part of the allowed set of staking contracts.
	///
	/// @param stakeToken The address of the staking contract.
	error DuplicatedStakingContract(address stakeToken);

	/// @notice Indicates that a token is disabled for staking.
	///
	/// @param stakeToken The address of the staking contract disabled for staking.
	error DisabledStakingContract(address stakeToken);

	/// @notice Indicates that a deposit operation is taking place in the same block as the current attempted operation.
	error DepositSameBlock();

	/// @notice Indicates that the minimum collateralization is under the minimum limit.
	error MinimumCollateralizationBreached();

	/// @notice Indicates that the caller is not whitelisted.
	error OnlyWhitelistAllowed();

	/// @notice Indicates that the caller is not a staking contract.
	error OnlyStakingContractAllowed();

	/// @notice Indicates that the caller is not the zoo.
	error OnlyZooAllowed();
}

