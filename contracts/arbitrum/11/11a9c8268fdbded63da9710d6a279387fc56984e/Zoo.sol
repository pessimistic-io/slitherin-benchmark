// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Math } from "./Math.sol";

import { IVaultAdapter } from "./IVaultAdapter.sol";
import { IControllerZooMinimal } from "./IControllerZooMinimal.sol";
import { IERC20TokenReceiver } from "./IERC20TokenReceiver.sol";

import { PausableAccessControl } from "./PausableAccessControl.sol";
import { TokenUtils } from "./TokenUtils.sol";
import { SafeCast } from "./SafeCast.sol";
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
	}

	/// @notice The scalar used for conversion of integral numbers to fixed point numbers.
	uint256 public constant FIXED_POINT_SCALAR = 1e18;

	/// @notice The token that this contract is using as the collateral asset.
	address public immutable collatToken;

	/// @notice The token that this contract is using as the native token.
	address public immutable nativeToken;

	/// @notice The token that this contract is using as the debt asset.
	address public immutable debtToken;

	/// @notice The total amount the native token deposited into the system that is owned by external users.
	uint256 public totalDeposited;

	/// @notice The maximum value allowed for {totalDebt}.
	int256 public maxDebt;

	/// @notice The current debt owned by the zoo contract.
	/// @notice The debt is calculated as the difference between the total amount of debt tokens minted by the contract and the total amount of debt tokens transferred to the zoo.
	int256 public totalDebt;

	/// @notice The address of the contract which will control the health of user position.
	/// @notice A callback from the controller is called before and after each user operation. The function call reverts if the action is not allowed by the controller.
	address public controller;

	/// @notice The address of the contract which will convert synthetic tokens back into native tokens.
	address public keeper;

	/// @notice The address of the contract which will manage the native token deposited into vaults.
	address public vaultAdapter;

	/// @notice The accumlated yield weight used to calculate users' rewards
	uint256 public accumulatedYieldWeight;

	/// @notice A mapping of all of the user CDPs. If a user wishes to have multiple CDPs they will have to either
	/// create a new address or set up a proxy contract that interfaces with this contract.
	mapping(address => UserInfo) private _userInfos;

	constructor(
		address _collatToken,
		address _nativeToken,
		address _debtToken
	) {
		collatToken = _collatToken;
		nativeToken = _nativeToken;
		debtToken = _debtToken;
	}

	function setVaultAdapter(address _vaultAdapter) external {
		_onlyAdmin();
		if (_vaultAdapter == address(0)) {
			revert ZeroAddress();
		}

		vaultAdapter = _vaultAdapter;
	}

	/// @notice Sets the address of the controller.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	///
	/// @notice Emits a {ControllerUpdated} event.
	///
	/// @param _controller The address of the new controller.
	function setController(address _controller) external {
		_onlyAdmin();
		if (_controller == address(0)) {
			revert ZeroAddress();
		}
		controller = _controller;

		emit ControllerUpdated(_controller);
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

	/// @inheritdoc IERC20TokenReceiver
	function onERC20Received(address _token, uint256 _amount) external nonReentrant {
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
	/// @param _amount the amount of tokens to deposit.
	function deposit(uint256 _amount) external nonReentrant {
		_checkNotPaused();
		if (_amount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		address _controller = controller;
		IControllerZooMinimal(_controller).controlBeforeDeposit(address(this), msg.sender, _amount);

		_deposit(msg.sender, _amount);

		IControllerZooMinimal(_controller).controlAfterDeposit(address(this), msg.sender, _amount);
	}

	/// @notice Withdraws `_amount` of tokens from the zoo.
	/// @notice Transfers `_amount` of tokens from the zoo to the caller and decreases caller collateral position by an equivalent amount.
	/// @notice Controller is called before and after to check if the action is allowed.
	///
	/// @notice Reverts with an {ZeroValue} error if the withdrawn amount is 0.
	///
	/// @notice Emits a {TokensWithdrawn} event.
	///
	/// @param _amount the amount of tokens to withdraw.
	function withdraw(uint256 _amount) external nonReentrant {
		if (_amount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		address _controller = controller;
		IControllerZooMinimal(_controller).controlBeforeWithdraw(address(this), msg.sender, _amount);

		_withdraw(msg.sender, _amount);

		IControllerZooMinimal(_controller).controlAfterWithdraw(address(this), msg.sender, _amount);
	}

	function selfLiquidate(uint256 _amount) external nonReentrant {
		if (_amount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		// Computes effective debt reduction allowed for user
		uint256 _liquidateAmount = _getEffectiveDebtReducedFor(msg.sender, _amount);

		address _controller = controller;
		IControllerZooMinimal(_controller).controlBeforeLiquidate(address(this), msg.sender, _liquidateAmount);

		_selfLiquidate(msg.sender, _liquidateAmount);

		IControllerZooMinimal(_controller).controlAfterLiquidate(address(this), msg.sender, _liquidateAmount);
	}

	/// @notice Mints `_amount` of debt tokens and transfers them to the caller.
	/// @notice Controller is called before and after to check if the action is allowed.
	///
	/// @notice Reverts with an {ZeroValue} error if the minted amount is 0.
	///
	/// @notice Emits a {TokensMinted} event.
	///
	/// @param _amount the amount of debt tokens to mint.
	function mint(uint256 _amount) external nonReentrant {
		_checkNotPaused();
		if (_amount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		address _controller = controller;
		IControllerZooMinimal(_controller).controlBeforeMint(address(this), msg.sender, _amount);

		_mint(msg.sender, _amount);

		IControllerZooMinimal(_controller).controlAfterMint(address(this), msg.sender, _amount);
	}

	/// @notice Burns `_amount` of debt tokens from the caller.
	/// @notice If the user debt is lower than the amount, then the entire debt is burned.
	/// @notice Controller is called before and after to check if the action is allowed.
	///
	/// @notice Reverts with an {ZeroValue} error if the burned amount is 0.
	///
	/// @notice Emits a {TokensBurned} event.
	///
	/// @param _amount The amount of debt tokens to burn.
	function burn(uint256 _amount) external nonReentrant {
		if (_amount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		// Computes effective debt reduction allowed for user
		uint256 _burnAmount = _getEffectiveDebtReducedFor(msg.sender, _amount);

		address _controller = controller;
		IControllerZooMinimal(_controller).controlBeforeBurn(address(this), msg.sender, _burnAmount);

		_burn(msg.sender, _amount);

		IControllerZooMinimal(_controller).controlAfterBurn(address(this), msg.sender, _burnAmount);
	}

	function liquidate(address _toLiquidate) external {
		// Transfers GLP from liquidator
		// Computes amount to liquidate for user
	}

	/// @notice Allows controller to update distribution and user information.
	/// @notice Controller needs to gather synchronised informations from multiple sources to check if an action is allowed.
	///
	/// @notice Reverts with an {OnlyControllerAllowed} error if the caller is not the controller.
	///
	/// @notice _owner The address of the user to update.
	function sync(address _owner) external {
		_distribute();
		_update(_owner);
	}

	/// @notice Gets the total amount of tokens deposited and the total debt for `_owner`.
	///
	/// @param _owner The address of the account to query.
	///
	/// @return totalDeposit The amount of tokens deposited as a collateral.
	/// @return totalDebt The amount of debt contracted by the user.
	function userInfo(address _owner) external view returns (uint256, int256) {
		UserInfo storage _userInfo = _userInfos[_owner];

		uint256 _userTotalDeposited = _userInfo.totalDeposited;

		uint256 _earnedYield = ((accumulatedYieldWeight - _userInfo.lastAccumulatedYieldWeight) * _userTotalDeposited) /
			FIXED_POINT_SCALAR;

		int256 _userTotalDebt = _userInfo.totalDebt - SafeCast.toInt256(_earnedYield);
		return (_userTotalDeposited, _userTotalDebt);
	}

	function _deposit(address _user, uint256 _amount) internal {
		// Transfers tokens from user and deposits into the vault manager
		TokenUtils.safeTransferFrom(collatToken, _user, vaultAdapter, _amount);
		IVaultAdapter(vaultAdapter).deposit(_amount);

		// Increases deposit for user
		_increaseDepositFor(_user, _amount);

		emit TokensDeposited(_user, _amount);
	}

	function _withdraw(address _user, uint256 _amount) internal {
		// Decreases deposit for user
		_decreaseDepositFor(_user, _amount);

		// Transfers tokens from vault to user
		IVaultAdapter(vaultAdapter).withdraw(_user, _amount);

		emit TokensWithdrawn(_user, _amount);
	}

	function _selfLiquidate(address _user, uint256 _amount) internal {
		// Decreases deposit for user
		TokenUtils.safeTransferFrom(nativeToken, _user, address(this), _amount);

		// Decreases debt for user
		_increaseDebtFor(_user, -SafeCast.toInt256(_amount));

		// Transfers liquidated native tokens to the keeper
		_distributeToKeeper(_amount);

		emit TokensLiquidated(_user, _amount);
	}

	function _mint(address _user, uint256 _amount) internal {
		// Increases debt for user
		_increaseDebtFor(_user, SafeCast.toInt256(_amount));

		// Mints debt tokens
		_mintDebtToken(_user, _amount);

		emit TokensMinted(_user, _amount);
	}

	function _burn(address _user, uint256 _amount) internal {
		// Burns debt tokens from user
		_burnDebtToken(_user, _amount);

		// Decreases debt for user
		_increaseDebtFor(_user, -SafeCast.toInt256(_amount));

		emit TokensBurned(_user, _amount);
	}

	/// @notice Increases the amount of collateral collatToken deposited in the platform by `_increasedAmount` for `_owner`.
	/// @notice Updates the total amount deposited in the platform.
	///
	/// @param _owner The address of the account to update deposit for.
	/// @param _increasedAmount The increase amount of asset deposited by `_owner`.
	function _increaseDepositFor(address _owner, uint256 _increasedAmount) internal {
		UserInfo storage _userInfo = _userInfos[_owner];
		_userInfo.totalDeposited += _increasedAmount;
		totalDeposited += _increasedAmount;
	}

	/// @notice Decreases the amount of collateral collatToken deposited in the platform by `_decreasedAmount` for `_owner`.
	/// @notice Updates the total amount deposited in the platform.
	///
	/// @param _owner The address of the account to update deposit for.
	/// @param _decreasedAmount The decrease amount of asset deposited by `_owner`.
	function _decreaseDepositFor(address _owner, uint256 _decreasedAmount) internal {
		UserInfo storage _userInfo = _userInfos[_owner];
		_userInfo.totalDeposited -= _decreasedAmount;
		totalDeposited -= _decreasedAmount;
	}

	/// @notice Increases the amount of debt by `_increasedAmount` for `_owner`.
	/// @notice As `_increasedAmount` can be a negative value, this function is also used to decreased the debt.
	/// @notice Updates the total debt from the plateform.
	///
	/// @notice Reverts with an {MaxDebtBreached} error if the platform debt is greater than the maximum allowed debt.
	///
	/// @param _owner The address of the account to update debt for.
	/// @param _amount The additional amount of debt (can be negative) owned by `_owner`.
	function _increaseDebtFor(address _owner, int256 _amount) internal {
		UserInfo storage _userInfo = _userInfos[_owner];
		_userInfo.totalDebt += _amount;
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

	/// @notice Distributes rewards deposited into the zoo by the vaultAdapter.
	/// @notice Fees are deducted from the rewards and sent to the fee receiver.
	/// @notice Remaining rewards reduce users' debts and are sent to the keeper.
	function _distribute() internal {
		uint256 _harvestedAmount = TokenUtils.safeBalanceOf(nativeToken, address(this));

		if (_harvestedAmount > 0) {
			// Updates users' debt
			uint256 _weight = (_harvestedAmount * FIXED_POINT_SCALAR) / totalDeposited;
			accumulatedYieldWeight += _weight;

			// Distributes harvest to keeper
			_distributeToKeeper(_harvestedAmount);
		}

		emit HarvestRewardDistributed(_harvestedAmount);
	}

	/// @notice Mints `_amount` of debt tokens and send them to `_recipient`.
	///
	/// @param _recipient The beneficiary of the minted tokens.
	/// @param _amount The amount of tokens to mint.
	function _mintDebtToken(address _recipient, uint256 _amount) internal {
		// Checks max debt breached
		int256 _totalDebt = totalDebt + SafeCast.toInt256(_amount);
		if (_totalDebt > maxDebt) {
			revert MaxDebtBreached();
		}
		totalDebt = _totalDebt;
		// Mints debt tokens to user
		TokenUtils.safeMint(debtToken, _recipient, _amount);
	}

	/// @notice Burns `_amount` of debt tokens from `_origin`.
	///
	/// @param _origin The origin of the burned tokens.
	/// @param _amount The amount of tokens to burn.
	function _burnDebtToken(address _origin, uint256 _amount) internal {
		TokenUtils.safeBurnFrom(debtToken, _origin, _amount);
		totalDebt -= SafeCast.toInt256(_amount);
	}

	/// @notice Distributes `_amount` of vault tokens to the keeper.
	///
	/// @param _amount The amount of vault tokens to send to the keeper.
	function _distributeToKeeper(uint256 _amount) internal {
		// Reduces platform debt
		totalDebt -= SafeCast.toInt256(_amount);

		address _keeper = keeper;
		TokenUtils.safeTransfer(nativeToken, _keeper, _amount);
		IERC20TokenReceiver(_keeper).onERC20Received(nativeToken, _amount);
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

	/// @notice Emitted when the controller address is updated.
	///
	/// @param controller The address of the controller.
	event ControllerUpdated(address controller);

	/// @notice Emitted when the keeper address is updated.
	///
	/// @param keeper The address of the keeper.
	event KeeperUpdated(address keeper);

	/// @notice Emitted when the max debt is updated.
	///
	/// @param maxDebtAmount The maximum debt.
	event MaxDebtUpdated(int256 maxDebtAmount);

	/// @notice Emitted when rewards are distributed.
	///
	/// @param amount The amount of native tokens distributed.
	event HarvestRewardDistributed(uint256 amount);

	/// @notice Indicates that a mint operation failed because the max debt is breached.
	error MaxDebtBreached();

	/// @notice Indiciated that the user does not have any debt.
	///
	/// @param debt The current debt owner by the user.
	error NoPositiveDebt(int256 debt);
}

