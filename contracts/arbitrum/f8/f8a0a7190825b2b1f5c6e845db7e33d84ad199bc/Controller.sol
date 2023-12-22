// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import { IOracle } from "./IOracle.sol";
import { IWhitelist } from "./IWhitelist.sol";
import { IZooMinimal } from "./IZooMinimal.sol";
import { IERC20StakerMinimal } from "./IERC20StakerMinimal.sol";

import { TokenUtils } from "./TokenUtils.sol";
import { AdminAccessControl } from "./AdminAccessControl.sol";
import { Sets } from "./Sets.sol";
import "./Errors.sol";

contract Controller is AdminAccessControl, ReentrancyGuard {
	/// @notice A structure to store the informations related to an account.
	struct UserInfo {
		/// @notice The set of staked tokens.
		Sets.AddressSet stakings;
		/// @notice Last block number a deposit was made.
		uint256 lastDeposit;
	}

	/// @notice A structure to store the informations related to a staking contract.
	/// @notice Staking contract must have a precision equals to debt token decimals.
	struct StakeTokenParam {
		// Gives the multiplier associated with staking amount to compute user staking bonus.
		uint256 multiplier;
		// Factor to express staked token amount with debt token precision.
		uint256 conversionFactor;
		// A flag to indicate if the staking is enabled.
		bool enabled;
	}

	struct PriceFeed {
		// The address of the oracle providing price for collat token.
		address oracle;
		// The conversion factor between price precision and debt token precision.
		uint256 conversionFactor;
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

	/// @notice The token that this contract is using as the debt asset.
	address public immutable debtToken;

	/// @notice The address of the zoo contract which will manage the deposit/withdraw/mint/burn actions.
	address public zoo;

	/// @notice The address of the contract which will manage the whitelisted contracts with access to the actions.
	address public whitelist;

	/// @notice The address of the contract which will provide price feed expressed in debt token for collateral token.
	PriceFeed private _priceFeed;

	/// @notice The list of supported tokens to stake. Staked tokens are eligible for collateral ratio boost.
	Sets.AddressSet private _supportedStakings;

	/// @notice A mapping between a stake token address and the associated stake token parameters.
	mapping(address => StakeTokenParam) private _stakings;

	/// @notice A mapping of all of the user CDPs. If a user wishes to have multiple CDPs they will have to either
	/// create a new address or set up a proxy contract that interfaces with this contract.
	mapping(address => UserInfo) private _userInfos;

	constructor(
		address _debtToken,
		uint256 _minimumSafeGuardCollateralization,
		uint256 _minimumAdjustedCollateralization
	) {
		debtToken = _debtToken;
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

	/// @notice Sets the address of the oracle contract.
	///
	/// @notice Reverts if the caller does not have the admin role.
	///
	/// @param _oracle The address of the new oracle.
	function setPriceFeed(address _oracle) external {
		_onlyAdmin();
		if (_oracle == address(0)) {
			revert ZeroAddress();
		}

		uint8 _debtTokenDecimals = TokenUtils.expectDecimals(debtToken);
		uint8 _priceDecimals = IOracle(_oracle).decimals();
		uint256 _conversionFactor = 10**(_debtTokenDecimals - _priceDecimals);

		_priceFeed = PriceFeed({ oracle: _oracle, conversionFactor: _conversionFactor });

		emit PriceFeedUpdated(_oracle, _conversionFactor);
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
	function addSupportedStaking(
		address _staking,
		uint256 _decimals,
		uint256 _multiplier
	) external {
		_onlyAdmin();

		if (Sets.contains(_supportedStakings, _staking)) {
			revert DuplicatedStakingContract(_staking);
		}

		uint8 _debtTokenDecimals = TokenUtils.expectDecimals(debtToken);

		uint256 _conversionFactor = 10**(_debtTokenDecimals - _decimals);

		_stakings[_staking] = StakeTokenParam({
			multiplier: _multiplier,
			conversionFactor: _conversionFactor,
			enabled: false
		});

		Sets.add(_supportedStakings, _staking);

		emit StakingAdded(_staking, _conversionFactor);
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

		UserInfo storage _userInfo = _userInfos[_owner];
		if (block.number <= _userInfo.lastDeposit) {
			revert DepositSameBlock();
		}
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

		_userInfos[_owner].lastDeposit = block.number;
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

		Sets.add(_userInfos[_owner].stakings, _staking);
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

		if (IERC20StakerMinimal(_staking).balanceOf(_owner) == 0) {
			Sets.remove(_userInfos[_owner].stakings, _staking);
		}
	}

	/// @notice Gets the address of the price feed.
	function getPriceFeed() external view returns (address) {
		return _priceFeed.oracle;
	}

	/// @notice Gets the list of staked tokens by `_owner`.
	///
	/// @param _owner The address of the user to query the staked tokens for.
	function getStakingsFor(address _owner) external view returns (address[] memory) {
		return _userInfos[_owner].stakings.values;
	}

	/// @notice Gets the list of supported staked tokens.
	function getSupportedStakings() external view returns (address[] memory) {
		return _supportedStakings.values;
	}

	/// @notice Checks if a token is available for staking.
	///
	/// @return true if the token can be staked.
	function isSupportedStaking(address _staking) external view returns (bool) {
		return Sets.contains(_supportedStakings, _staking);
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

	function _validate(address _owner) internal view {
		(uint256 _deposit, int256 _debt) = IZooMinimal(zoo).userInfo(_owner);

		// If no debt the position is valid
		if (_debt <= 0) {
			return;
		}

		// Total value normalized in debt token precision
		uint256 _totalValue = _normalizeToDebt(
			IOracle(_priceFeed.oracle).getPrice(_deposit),
			_priceFeed.conversionFactor
		);

		// Checks direct debt factor
		uint256 _rawCollateralization = (_totalValue * FIXED_POINT_SCALAR) / uint256(_debt);

		if (_rawCollateralization < minimumSafeGuardCollateralization) {
			revert SafeGuardCollateralizationBreached();
		}
		// No needs to check staking bonus if deposit is enough
		uint256 _minimumAdjustedCollateralization = minimumAdjustedCollateralization;
		if (_rawCollateralization >= _minimumAdjustedCollateralization) {
			return;
		}
		// Check debt factor adjusted with staking
		uint256 _stakingBonus = _getStakingBonusFor(_owner);

		uint256 _adjustedCollateralization = ((_totalValue + _stakingBonus) * FIXED_POINT_SCALAR) / uint256(_debt);

		if (_adjustedCollateralization < _minimumAdjustedCollateralization) {
			revert AdjustedCollateralizationBreached();
		}
	}

	function _getStakingBonusFor(address _owner) internal view returns (uint256) {
		uint256 _score = 0;

		address[] memory _stakingTokenList = _userInfos[_owner].stakings.values;
		for (uint256 i = 0; i < _stakingTokenList.length; ++i) {
			StakeTokenParam storage _param = _stakings[_stakingTokenList[i]];
			if (_param.enabled) {
				// Get user lock amount
				uint256 _stakingTokenBalance = IERC20StakerMinimal(_stakingTokenList[i]).balanceOf(_owner);
				if (_stakingTokenBalance > 0) {
					uint256 _normalizedStakingTokenBalance = _normalizeToDebt(
						_stakingTokenBalance,
						_param.conversionFactor
					);

					_score += (_normalizedStakingTokenBalance * _param.multiplier) / FIXED_POINT_SCALAR;
				}
			}
		}
		return _score;
	}

	function _normalizeToDebt(uint256 _amount, uint256 _conversionFactor) internal pure returns (uint256) {
		return _amount * _conversionFactor;
	}

	function _checkSupportedStaking(address _staking) internal view {
		if (!Sets.contains(_supportedStakings, _staking)) {
			revert UnsupportedStakingContract(_staking);
		}
	}

	function _checkEnabledStaking(address _staking) internal view {
		if (!_stakings[_staking].enabled) {
			revert DisabledStakingContract(_staking);
		}
	}

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

	function _onlyStakingContract() internal view {
		if (!Sets.contains(_supportedStakings, msg.sender)) {
			revert OnlyStakingContractAllowed();
		}
	}

	function _onlyZoo() internal view {
		if (zoo != msg.sender) {
			revert OnlyZooAllowed();
		}
	}

	event MinimumSafeGuardCollateralizationUpdated(uint256 _minimumSafeGuardCollateralization);

	event MinimumAdjustedCollateralizationUpdated(uint256 _minimumAdjustedCollateralization);

	event StakingAdded(address staker, uint256 conversionFactor);

	event StakingEnableUpdated(address staker, bool enabled);

	event StakingMultiplierUpdated(address staker, uint256 multiplier);

	event WhitelistUpdated(address whitelist);

	event ZooUpdated(address zoo);

	event PriceFeedUpdated(address oracle, uint256 conversionFactor);

	error SafeGuardCollateralizationBreached();

	error AdjustedCollateralizationBreached();

	error UnsupportedStakingContract(address stakeToken);

	error DuplicatedStakingContract(address stakeToken);

	error DisabledStakingContract(address stakeToken);

	error DepositSameBlock();

	error MinimumCollateralizationBreached();

	error OnlyWhitelistAllowed();

	error OnlyStakingContractAllowed();

	error OnlyZooAllowed();
}

