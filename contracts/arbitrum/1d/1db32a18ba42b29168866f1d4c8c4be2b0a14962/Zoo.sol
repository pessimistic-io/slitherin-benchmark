// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Math } from "./Math.sol";

import { IWhitelist } from "./IWhitelist.sol";
import { IOracle } from "./IOracle.sol";
import { IVaultManagerMinimal } from "./IVaultManagerMinimal.sol";
import { IERC20StakerMinimal } from "./IERC20StakerMinimal.sol";
import { IERC20TokenReceiver } from "./IERC20TokenReceiver.sol";

import { PausableAccessControl } from "./PausableAccessControl.sol";
import { TokenUtils } from "./TokenUtils.sol";
import { SafeCast } from "./SafeCast.sol";
import { Sets } from "./Sets.sol";
import "./Errors.sol";

contract Zoo is IERC20TokenReceiver, PausableAccessControl, ReentrancyGuard {
	/// @notice A structure to store the informations related to a user CDP.
	struct UserInfo {
		/// @notice Total user deposit.
		uint256 totalDeposited;
		/// @notice Total user debt.
		int256 totalDebt;
		/// @notice Weight used to calculate % of total deposited earned by user since last update.
		uint256 lastAccumulatedYieldWeight;
		/// @notice The set of staked tokens.
		Sets.AddressSet stakings;
		/// @notice The balance for each staked token.
		mapping(address => uint256) stakes;
		/// @notice Last block number a deposit was made.
		uint256 lastDeposit;
	}

	/// @notice A structure to store the informations related to a staking contract.
	/// @notice Staking contract must have a precision equals to debt token decimals.
	struct StakeTokenParam {
		// Gives the multiplier associated with staking amount to compute user staking bonus.
		uint256 multiplier;
		// Factor to express staked token amount with debt token precision
		uint256 conversionFactor;
		// A flag to indicate if the staking is enabled.
		bool enabled;
	}

	struct PriceFeed {
		address oracle;
		uint256 conversionFactor;
	}

	/// @notice The scalar used for conversion of integral numbers to fixed point numbers.
	uint256 public constant FIXED_POINT_SCALAR = 1e18;

	/// @notice The minimum value that the collateralization limit can be set to by the admin. This is a safety rail to prevent the collateralization from being set to a value which breaks the system.
	/// This value is equal to 100%.
	uint256 public constant MINIMUM_COLLATERALIZATION = 1e18;

	/// @notice Factor to convert native token amount into debt token amount.
	/// @notice Debt token has a precision of 18 decimals.
	uint256 public immutable CONVERSION_FACTOR;

	/// @notice The token that this contract is using as the collateral asset.
	address public immutable collatToken;

	/// @notice The token that this contract is using as the native token.
	address public immutable nativeToken;

	/// @notice The token that this contract is using as the debt asset.
	address public immutable debtToken;

	/// @notice The address of the contract which will manage the native token deposited into vaults.
	address public immutable vaultManager;

	/// @notice The maximum value allowed for {totalDebt}.
	int256 public maxDebt;

	/// @notice The current debt owned by the zoo contract.
	/// @notice The debt is calculated as the difference between the total amount of debt tokens minted by the contract and the total amount of debt tokens transferred to the zoo.
	int256 public totalDebt;

	/// @notice The address of the contract which will manage the whitelisted contracts with access to the actions.
	address public whitelist;

	/// @notice The address of the contract which will convert synthetic tokens back into native tokens.
	address public keeper;

	/// @notice The minimum collateralization ratio allowed. Calculated as user deposit / user debt.
	uint256 public minimumSafeGuardCollateralization;

	/// @notice The minimum adjusted collateralization ratio. Calculates as (user deposit + user staking bonus) / user debt.
	uint256 public minimumAdjustedCollateralization;

	/// @notice The total amount the native token deposited into the system that is owned by external users.
	uint256 public totalDeposited;

	/// @notice The accumlated yield weight used to calculate users' rewards
	uint256 public accumulatedYieldWeight;

	/// @notice The address of the contract which will provide price feed expressed in debt token for collateral token.
	PriceFeed private _priceFeed;

	/// @notice The list of supported tokens to stake. Staked tokens are eligible for collateral ratio boost.
	Sets.AddressSet private _supportedStaking;

	/// @notice A mapping between a stake token address and the associated stake token parameters.
	mapping(address => StakeTokenParam) private _stakers;

	/// @notice A mapping of all of the user CDPs. If a user wishes to have multiple CDPs they will have to either
	/// create a new address or set up a proxy contract that interfaces with this contract.
	mapping(address => UserInfo) private _userInfos;

	constructor(
		address _collatToken,
		address _nativeToken,
		address _debtToken,
		address _vaultManager,
		uint256 _minimumSafeGuardCollateralization,
		uint256 _minimumAdjustedCollateralization,
		int256 _maxDebt
	) {
		collatToken = _collatToken;
		nativeToken = _nativeToken;
		debtToken = _debtToken;
		vaultManager = _vaultManager;
		minimumSafeGuardCollateralization = _minimumSafeGuardCollateralization;
		minimumAdjustedCollateralization = _minimumAdjustedCollateralization;
		maxDebt = _maxDebt;

		uint8 _nativeTokenDecimals = TokenUtils.expectDecimals(_nativeToken);
		uint8 _debtTokenDecimals = TokenUtils.expectDecimals(_debtToken);

		CONVERSION_FACTOR = 10**(_debtTokenDecimals - _nativeTokenDecimals);
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

	/// @notice Sets the address of the keeper.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	/// @notice Reverts with an {ZeroAddress} error if the new keeper is the 0 address.
	///
	/// @notice Emits a {KeeperUpdated} event.
	///
	/// @param _keeper The address of the new keeper.
	function setKeeper(address _keeper) external {
		_onlyAdmin();
		if (_keeper == address(0)) {
			revert ZeroAddress();
		}
		keeper = _keeper;

		emit KeeperUpdated(_keeper);
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

	/// @notice Sets the maximum debt.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	///
	/// @notice Emits a {MaxDebtUpdated} event.
	///
	/// @param _maxDebt The new max debt.
	function setMaxDebt(int256 _maxDebt) external {
		_onlyAdmin();
		maxDebt = _maxDebt;

		emit MaxDebtUpdated(_maxDebt);
	}

	/// @notice Adds `_staker` to the set of staker contracts with a multiplier of `_multiplier`.
	///
	/// @notice Reverts if `_staker` is already in the set of staker.
	/// @notice Reverts if the caller does not have the admin role.
	///
	/// @param _staker The address of the staking contract.
	/// @param _multiplier the multiplier associated with the staking contract.
	function addSupportedStaking(
		address _staker,
		uint256 _decimals,
		uint256 _multiplier
	) external {
		_onlyAdmin();
		if (Sets.contains(_supportedStaking, _staker)) {
			revert DuplicatedStakingContract(_staker);
		}

		uint8 _debtTokenDecimals = TokenUtils.expectDecimals(debtToken);

		uint256 _conversionFactor = 10**(_debtTokenDecimals - _decimals);

		_stakers[_staker] = StakeTokenParam({
			multiplier: _multiplier,
			conversionFactor: _conversionFactor,
			enabled: false
		});

		Sets.add(_supportedStaking, _staker);

		emit StakingAdded(_staker, _conversionFactor);
		emit StakingMultiplierUpdated(_staker, _multiplier);
		emit StakingEnableUpdated(_staker, false);
	}

	/// @notice Sets the multiplier of `_staker` to `_multiplier`.
	///
	/// @notice Reverts if `_staker` is not a supported stake token.
	/// @notice Reverts if the caller does not have the admin role.
	///
	/// @param _staker The address of the token.
	/// @param _multiplier The value of the multiplier associated with the staking token.
	function setStakingMultiplier(address _staker, uint256 _multiplier) external {
		_onlyAdmin();
		_checkSupportedStaking(_staker);

		_stakers[_staker].multiplier = _multiplier;

		emit StakingMultiplierUpdated(_staker, _multiplier);
	}

	/// @notice Sets the status of `_staker` to `_enabled`.
	/// @notice Users can stake tokens into the zoo to increase the amount of debt token they can borrow.
	///
	/// @notice Reverts if `_staker` is not a supported stake token.
	/// @notice Reverts if the caller does not have the admin role.
	///
	/// @param _staker The address of the token
	/// @param _enabled True if `_staker` is added to the set of staked tokens.
	function setStakingEnabled(address _staker, bool _enabled) external {
		_onlyAdmin();
		_checkSupportedStaking(_staker);

		_stakers[_staker].enabled = _enabled;

		emit StakingEnableUpdated(_staker, _enabled);
	}

	/// @inheritdoc IERC20TokenReceiver
	function onERC20Received(address _token, uint256 _amount) external nonReentrant {
		_distribute();
	}

	function distribute() external nonReentrant {
		_distribute();
	}

	/// @notice Deposits `_amount` of tokens into the zoo.
	/// @notice Transfers `_amount` of tokens from the caller to the zoo and increases caller collateral position by an equivalent amount.
	/// @notice Controller is called before and after to check if the action is allowed.
	///
	/// @notice Reverts with an {ContractPaused} error if the contract is in pause state.
	/// @notice Reverts with an {ZeroValue} error if the deposited amount is 0.
	///
	/// @notice Emits a {TokensDeposited} event.
	///
	/// @param _collatAmount the amount of collat tokens to deposit.
	function deposit(uint256 _collatAmount) external nonReentrant {
		_onlyWhitelisted(msg.sender);
		_checkNotPaused();
		if (_collatAmount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		_deposit(msg.sender, _collatAmount);
	}

	/// @notice Withdraws `_amount` of tokens from the zoo.
	/// @notice Transfers `_amount` of tokens from the zoo to the caller and decreases caller collateral position by an equivalent amount.
	/// @notice Controller is called before and after to check if the action is allowed.
	///
	/// @notice Reverts with an {ZeroValue} error if the withdrawn amount is 0.
	///
	/// @notice Emits a {TokensWithdrawn} event.
	///
	/// @param _collatAmount the amount of tokens to withdraw.
	function withdraw(uint256 _collatAmount) external nonReentrant {
		_onlyWhitelisted(msg.sender);
		if (_collatAmount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		_withdraw(msg.sender, _collatAmount);
		_validate(msg.sender);
	}

	/// @notice  Liquidates `_amount` of debt tokens from the caller.
	///
	/// @param _debtAmount The amount of debt tokens to liquidate
	function selfLiquidate(uint256 _debtAmount) external nonReentrant {
		_onlyWhitelisted(msg.sender);
		_checkNotPaused();
		if (_debtAmount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		// Computes effective debt reduction allowed for user
		uint256 _liquidateDebtAmount = _getEffectiveDebtReducedFor(msg.sender, _debtAmount);

		_selfLiquidate(msg.sender, _liquidateDebtAmount);
	}

	function liquidate(address _toLiquidate) external {
		_onlyWhitelisted(msg.sender);
		// Transfers GLP from liquidator
		// Computes amount to liquidate for user
	}

	/// @notice Mints `_amount` of debt tokens and transfers them to the caller.
	/// @notice Controller is called before and after to check if the action is allowed.
	///
	/// @notice Reverts with an {ZeroValue} error if the minted amount is 0.
	///
	/// @notice Emits a {TokensMinted} event.
	///
	/// @param _debtAmount the amount of debt tokens to mint.
	function mint(uint256 _debtAmount) external nonReentrant {
		_onlyWhitelisted(msg.sender);
		_checkNotPaused();
		if (_debtAmount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		_mint(msg.sender, _debtAmount);
		_validate(msg.sender);
	}

	/// @notice Burns `_amount` of debt tokens from the caller.
	/// @notice If the user debt is lower than the amount, then the entire debt is burned.
	/// @notice Controller is called before and after to check if the action is allowed.
	///
	/// @notice Reverts with an {ZeroValue} error if the burned amount is 0.
	///
	/// @notice Emits a {TokensBurned} event.
	///
	/// @param _debtAmount The amount of debt tokens to burn.
	function burn(uint256 _debtAmount) external nonReentrant {
		_onlyWhitelisted(msg.sender);
		if (_debtAmount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		// Computes effective debt reduction allowed for user
		uint256 _burnDebtAmount = _getEffectiveDebtReducedFor(msg.sender, _debtAmount);

		_burn(msg.sender, _burnDebtAmount);
	}

	function stake(address _staker, uint256 _amount) external nonReentrant {
		_onlyWhitelisted(msg.sender);
		_checkNotPaused();
		if (_amount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		_stake(msg.sender, _staker, _amount);
	}

	function unstake(address _staker, uint256 _amount) external nonReentrant {
		_onlyWhitelisted(msg.sender);
		if (_amount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		_unstake(msg.sender, _staker, _amount);

		_validate(msg.sender);
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
	function isSupportedStaking(address _staker) external view returns (bool) {
		return Sets.contains(_supportedStaking, _staker);
	}

	/// @notice Gets the parameters associated with a stake token.
	///
	/// @param _staker The address of the stake token to query.
	///
	/// @return The parameters of the stake token.
	function getStakingParam(address _staker) external view returns (StakeTokenParam memory) {
		return _stakers[_staker];
	}

	/// @notice Gets the total amount of tokens deposited and the total debt for `_owner`.
	///
	/// @param _owner The address of the account to query.
	///
	/// @return totalDeposit The amount of tokens deposited as a collateral.
	/// @return totalDebt The amount of debt contracted by the user.
	function userInfo(address _owner)
		external
		view
		returns (
			uint256,
			int256,
			uint256
		)
	{
		UserInfo storage _userInfo = _userInfos[_owner];

		uint256 _userTotalDeposited = _userInfo.totalDeposited;

		uint256 _earnedYield = ((accumulatedYieldWeight - _userInfo.lastAccumulatedYieldWeight) * _userTotalDeposited) /
			FIXED_POINT_SCALAR;

		int256 _userTotalDebt = _userInfo.totalDebt - SafeCast.toInt256(_earnedYield);

		uint256 _bonus = _getStakingBonusFor(_owner);

		return (_userTotalDeposited, _userTotalDebt, _bonus);
	}

	function _deposit(address _user, uint256 _collatAmount) internal {
		TokenUtils.safeTransferFrom(collatToken, _user, vaultManager, _collatAmount);
		IVaultManagerMinimal(vaultManager).deposit(_collatAmount);

		// Increases deposit for user
		_increaseDepositFor(_user, _collatAmount);

		_userInfos[_user].lastDeposit = block.number;

		emit TokensDeposited(_user, _collatAmount);
	}

	function _withdraw(address _user, uint256 _collatAmount) internal {
		_checkDepositSameBlock(_user);

		// Decreases deposit for user
		_decreaseDepositFor(_user, _collatAmount);

		// Transfers tokens from vault to user
		IVaultManagerMinimal(vaultManager).withdraw(_user, _collatAmount);

		emit TokensWithdrawn(_user, _collatAmount);
	}

	function _selfLiquidate(address _user, uint256 _debtAmount) internal {
		// Decreases deposit for user
		uint256 _nativeAmount = _normalizeDebtToNative(_debtAmount);
		TokenUtils.safeTransferFrom(nativeToken, _user, address(this), _nativeAmount);

		// Decreases debt for user
		_increaseDebtFor(_user, -SafeCast.toInt256(_debtAmount));

		// Transfers liquidated native tokens to the keeper
		_distributeToKeeper(_nativeAmount);

		emit TokensLiquidated(_user, _debtAmount);
	}

	function _mint(address _user, uint256 _debtAmount) internal {
		// Increases debt for user
		_increaseDebtFor(_user, SafeCast.toInt256(_debtAmount));

		// Mints debt tokens
		_mintDebtToken(_user, _debtAmount);

		emit TokensMinted(_user, _debtAmount);
	}

	function _burn(address _user, uint256 _debtAmount) internal {
		// Burns debt tokens from user
		_burnDebtToken(_user, _debtAmount);

		// Decreases debt for user
		_increaseDebtFor(_user, -SafeCast.toInt256(_debtAmount));

		emit TokensBurned(_user, _debtAmount);
	}

	function _stake(
		address _user,
		address _staker,
		uint256 _amount
	) internal {
		_checkSupportedStaking(_staker);
		_checkEnabledStaking(_staker);

		address _token = IERC20StakerMinimal(_staker).token();
		TokenUtils.safeTransferFrom(_token, _user, _staker, _amount);
		IERC20StakerMinimal(_staker).stake(_user);

		Sets.add(_userInfos[_user].stakings, _staker);
	}

	function _unstake(
		address _user,
		address _staker,
		uint256 _amount
	) internal {
		// TODO
		_checkSupportedStaking(_staker);

		IERC20StakerMinimal(_staker).unstake(_user, _amount);

		if (IERC20StakerMinimal(_staker).balanceOf(_user) == 0) {
			Sets.remove(_userInfos[_user].stakings, _staker);
		}
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

	/// @notice Checks if `_staker` is a supported staked token.
	///
	/// @notice Reverts if `_staker` is not supported.
	function _checkSupportedStaking(address _staker) internal view {
		if (!Sets.contains(_supportedStaking, _staker)) {
			revert UnsupportedStakingContract(_staker);
		}
	}

	/// @notice Checks if staking is enabled for `_staker`.
	///
	/// @notice Reverts if staking is disabled.
	function _checkEnabledStaking(address _staker) internal view {
		if (!_stakers[_staker].enabled) {
			revert DisabledStakingContract(_staker);
		}
	}

	/// @notice Increases the amount of collateral collatToken deposited in the platform by `_increasedAmount` for `_owner`.
	/// @notice Updates the total amount deposited in the platform.
	///
	/// @param _owner The address of the account to update deposit for.
	/// @param _collatAmount The increase amount of collateral asset deposited by `_owner`.
	function _increaseDepositFor(address _owner, uint256 _collatAmount) internal {
		UserInfo storage _userInfo = _userInfos[_owner];
		_userInfo.totalDeposited += _collatAmount;
		totalDeposited += _collatAmount;
	}

	/// @notice Decreases the amount of collateral collatToken deposited in the platform by `_decreasedAmount` for `_owner`.
	/// @notice Updates the total amount deposited in the platform.
	///
	/// @param _owner The address of the account to update deposit for.
	/// @param _collatAmount The decrease amount of collateral asset deposited by `_owner`.
	function _decreaseDepositFor(address _owner, uint256 _collatAmount) internal {
		UserInfo storage _userInfo = _userInfos[_owner];
		_userInfo.totalDeposited -= _collatAmount;
		totalDeposited -= _collatAmount;
	}

	/// @notice Increases the amount of debt by `_increasedAmount` for `_owner`.
	/// @notice As `_increasedAmount` can be a negative value, this function is also used to decreased the debt.
	/// @notice Updates the total debt from the plateform.
	///
	/// @notice Reverts with an {MaxDebtBreached} error if the platform debt is greater than the maximum allowed debt.
	///
	/// @param _owner The address of the account to update debt for.
	/// @param _debtAmount The additional amount of debt (can be negative) owned by `_owner`.
	function _increaseDebtFor(address _owner, int256 _debtAmount) internal {
		UserInfo storage _userInfo = _userInfos[_owner];
		_userInfo.totalDebt += _debtAmount;
	}

	/// @notice Mints `_amount` of debt tokens and send them to `_recipient`.
	///
	/// @param _recipient The beneficiary of the minted tokens.
	/// @param _debtAmount The amount of tokens to mint.
	function _mintDebtToken(address _recipient, uint256 _debtAmount) internal {
		// Checks max debt breached
		int256 _totalDebt = totalDebt + SafeCast.toInt256(_debtAmount);
		if (_totalDebt > maxDebt) {
			revert MaxDebtBreached();
		}
		totalDebt = _totalDebt;
		// Mints debt tokens to user
		TokenUtils.safeMint(debtToken, _recipient, _debtAmount);
	}

	/// @notice Burns `_amount` of debt tokens from `_origin`.
	///
	/// @param _origin The origin of the burned tokens.
	/// @param _debtAmount The amount of tokens to burn.
	function _burnDebtToken(address _origin, uint256 _debtAmount) internal {
		TokenUtils.safeBurnFrom(debtToken, _origin, _debtAmount);
		totalDebt -= SafeCast.toInt256(_debtAmount);
	}

	/// @notice Gets the effective debt reduction that will be attempted for `_owner`.
	/// @notice `_owner` wishes to liquidate/burn `_wishedDebtReducedAmount` amounts.
	/// @notice The effective attempted debt reduction is the minimum between the user debt and `_wishedDebtReducedAmount`.
	///
	/// @param _owner The address of the account that wants to reduce its debt.
	/// @param _wishedDebtReducedAmount The wished amount of debt the user wants to reimburse.
	///
	/// @return The amount of debt that `_owner` will effectively try to reimburse.
	function _getEffectiveDebtReducedFor(address _owner, uint256 _wishedDebtReducedAmount)
		internal
		view
		returns (uint256)
	{
		UserInfo storage _userInfo = _userInfos[_owner];

		int256 _userDebt = _userInfo.totalDebt;
		// Dont attempt to reduce if no debt
		if (_userDebt <= 0) {
			revert NoPositiveDebt(_userDebt);
		}

		// Dont attempt to reduce more than debt
		uint256 _effectiveDebtReduced = Math.min(_wishedDebtReducedAmount, uint256(_userDebt));

		return _effectiveDebtReduced;
	}

	/// @notice Updates the debt position for `_owner` according to the earned yield since the last update.
	///
	/// @param _owner the address of the user to update.
	function _update(address _owner) internal {
		UserInfo storage _userInfo = _userInfos[_owner];

		uint256 _earnedYield = ((accumulatedYieldWeight - _userInfo.lastAccumulatedYieldWeight) *
			_userInfo.totalDeposited) / FIXED_POINT_SCALAR;

		_userInfo.totalDebt -= SafeCast.toInt256(_earnedYield);
		_userInfo.lastAccumulatedYieldWeight = accumulatedYieldWeight;
	}

	/// @notice Distributes rewards deposited into the zoo by the vaultManager.
	/// @notice Fees are deducted from the rewards and sent to the fee receiver.
	/// @notice Remaining rewards reduce users' debts and are sent to the keeper.
	function _distribute() internal {
		uint256 _harvestedNativeAmount = TokenUtils.safeBalanceOf(nativeToken, address(this));

		if (_harvestedNativeAmount > 0) {
			// Repays users' debt
			uint256 _repaidDebtAmount = _normalizeNativeToDebt(_harvestedNativeAmount);
			uint256 _weight = (_repaidDebtAmount * FIXED_POINT_SCALAR) / totalDeposited;
			accumulatedYieldWeight += _weight;

			// Distributes harvest to keeper
			_distributeToKeeper(_harvestedNativeAmount);
		}

		emit HarvestRewardDistributed(_harvestedNativeAmount);
	}

	/// @notice Distributes `_amount` of vault tokens to the keeper.
	///
	/// @param _nativeAmount The amount of native tokens to send to the keeper.
	function _distributeToKeeper(uint256 _nativeAmount) internal {
		// Reduces platform debt
		totalDebt -= SafeCast.toInt256(_nativeAmount);

		address _keeper = keeper;
		TokenUtils.safeTransfer(nativeToken, _keeper, _nativeAmount);
		IERC20TokenReceiver(_keeper).onERC20Received(nativeToken, _nativeAmount);
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
		UserInfo storage _userInfo = _userInfos[_owner];

		uint256 _userDeposit = _userInfo.totalDeposited;
		int256 _userDebt = _userInfo.totalDebt;

		// If no debt the position is valid
		if (_userDebt <= 0) {
			return;
		}

		// Total value normalized in debt token precision
		uint256 _totalValue = _normaliseToDebt(
			IOracle(_priceFeed.oracle).getPrice(_userDeposit),
			_priceFeed.conversionFactor
		);

		// Checks direct debt factor
		uint256 _rawCollateralization = (_totalValue * FIXED_POINT_SCALAR) / uint256(_userDebt);

		if (_rawCollateralization < minimumSafeGuardCollateralization) {
			revert SafeGuardCollateralizationBreached();
		}
		// No needs to check staking bonus if deposit is enough
		uint256 _minimumAdjustedCollateralization = minimumAdjustedCollateralization;
		if (_rawCollateralization >= _minimumAdjustedCollateralization) {
			return;
		}
		// Check debt factor adjusted with staking
		uint256 _stakerBonus = _getStakingBonusFor(_owner);

		uint256 _adjustedCollateralization = ((_totalValue + _stakerBonus) * FIXED_POINT_SCALAR) / uint256(_userDebt);

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

		address[] memory _stakerTokenList = _userInfos[_owner].stakings.values;
		for (uint256 i = 0; i < _stakerTokenList.length; ++i) {
			StakeTokenParam storage _param = _stakers[_stakerTokenList[i]];
			if (_param.enabled) {
				// Get user lock amount
				uint256 _stakerTokenBalance = IERC20StakerMinimal(_stakerTokenList[i]).balanceOf(_owner);
				if (_stakerTokenBalance > 0) {
					uint256 _normalizedStakingTokenBalance = _normaliseToDebt(
						_stakerTokenBalance,
						_param.conversionFactor
					);

					_score += (_normalizedStakingTokenBalance * _param.multiplier) / FIXED_POINT_SCALAR;
				}
			}
		}
		return _score;
	}

	function _normaliseToDebt(uint256 _amount, uint256 _conversionFactor) internal pure returns (uint256) {
		return _amount * _conversionFactor;
	}

	function _normalizeNativeToDebt(uint256 _amount) internal view returns (uint256) {
		return _amount * CONVERSION_FACTOR;
	}

	function _normalizeDebtToNative(uint256 _amount) internal view returns (uint256) {
		return _amount / CONVERSION_FACTOR;
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

	/// @notice Emitted when `account` deposits `amount `tokens into the zoo.
	///
	/// @param account The address of the account owner.
	/// @param amount The amount of tokens deposited.
	event TokensDeposited(address indexed account, uint256 amount);

	/// @notice Emitted when `account` withdraws tokens.
	///
	/// @param account The address of the account owner.
	/// @param amount The amount of tokens requested to withdraw by `account`.
	event TokensWithdrawn(address indexed account, uint256 amount);

	/// @notice Emitted when `account` mints `amount` of debt tokens.
	///
	/// @param account The address of the account owner.
	/// @param amount The amount of debt tokens minted.
	event TokensMinted(address indexed account, uint256 amount);

	/// @notice Emitted when `account` burns `amount`debt tokens.
	///
	/// @param account The address of the account owner.
	/// @param amount The amount of debt tokens burned.
	event TokensBurned(address indexed account, uint256 amount);

	/// @notice Emitted when `account` liquidates a debt by using a part of it collateral position.
	///
	/// @param account The address of the account owner.
	/// @param requestedAmount the amount of tokens requested to pay debt by `account`.
	event TokensLiquidated(address indexed account, uint256 requestedAmount);

	/// @notice Emitted when the keeper address is updated.
	///
	/// @param keeper The address of the keeper.
	event KeeperUpdated(address keeper);

	/// @notice Emitted when the vault manager address is updated.
	///
	/// @param vaultManager The address of the vault manager.
	event VaultManagerUpdated(address vaultManager);

	/// @notice Emitted when the max debt is updated.
	///
	/// @param maxDebtAmount The maximum debt.
	event MaxDebtUpdated(int256 maxDebtAmount);

	/// @notice Emitted when rewards are distributed.
	///
	/// @param amount The amount of native tokens distributed.
	event HarvestRewardDistributed(uint256 amount);

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
	event StakingAdded(address staker, uint256 conversionFactor);

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

	/// @notice Emitted when the address of the oracle is updated.
	///
	/// @param oracle The address of the oracle.
	event PriceFeedUpdated(address oracle, uint256 conversionFactor);

	/// @notice Indicates that a mint operation failed because the max debt is breached.
	error MaxDebtBreached();

	/// @notice Indicates that the user does not have any debt.
	///
	/// @param debt The current debt owner by the user.
	error NoPositiveDebt(int256 debt);

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
}

