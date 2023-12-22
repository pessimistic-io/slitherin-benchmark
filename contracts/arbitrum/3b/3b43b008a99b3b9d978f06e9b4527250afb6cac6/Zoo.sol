// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Math } from "./Math.sol";

import { IVaultManagerMinimal } from "./IVaultManagerMinimal.sol";
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

	/// @notice Factor to convert native token amount into debt token amount.
	uint256 public immutable conversionFactor;

	/// @notice The token that this contract is using as the collateral asset.
	address public immutable collatToken;

	/// @notice The token that this contract is using as the native token.
	address public immutable nativeToken;

	/// @notice The token that this contract is using as the debt asset.
	address public immutable debtToken;

	/// @notice The total amount of native token deposited.
	uint256 public totalDeposited;

	/// @notice The maximum value allowed for {totalDebt}.
	int256 public maxDebt;

	/// @notice The current debt owned by the zoo contract.
	int256 public totalDebt;

	/// @notice The address of the contract which will control the users' actions.
	address public controller;

	/// @notice The address of the contract which will convert synthetic tokens back into native tokens.
	address public keeper;

	/// @notice The address of the contract which will manage the native token deposited into vaults.
	address public vaultManager;

	/// @notice The accumulated yield weight used to calculate users' rewards.
	uint256 private _accumulatedYieldWeight;

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

		uint8 _nativeTokenDecimals = TokenUtils.expectDecimals(_nativeToken);
		uint8 _debtTokenDecimals = TokenUtils.expectDecimals(_debtToken);

		conversionFactor = 10**(_debtTokenDecimals - _nativeTokenDecimals);
	}

	/// @notice Sets the address of the vault manager.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	///
	/// @notice Emits a {VaultManagerUpdated} event.
	///
	/// @param _vaultManager The address of the new vault manager.
	function setVaultManager(address _vaultManager) external {
		_onlyAdmin();
		if (_vaultManager == address(0)) {
			revert ZeroAddress();
		}

		vaultManager = _vaultManager;
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

	/// @notice Reduces users' debts and sends rewards to the keeper.
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
		_checkNotPaused();
		if (_collatAmount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		address _controller = controller;
		IControllerZooMinimal(_controller).controlBeforeDeposit(address(this), msg.sender, _collatAmount);

		_deposit(msg.sender, _collatAmount);

		IControllerZooMinimal(_controller).controlAfterDeposit(address(this), msg.sender, _collatAmount);
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
		if (_collatAmount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		address _controller = controller;
		IControllerZooMinimal(_controller).controlBeforeWithdraw(address(this), msg.sender, _collatAmount);

		_withdraw(msg.sender, _collatAmount);

		IControllerZooMinimal(_controller).controlAfterWithdraw(address(this), msg.sender, _collatAmount);
	}

	/// @notice  Liquidates `_amount` of debt tokens from the caller.
	///
	/// @param _debtAmount The amount of debt tokens to liquidate
	function selfLiquidate(uint256 _debtAmount) external nonReentrant {
		if (_debtAmount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		// Computes effective debt reduction allowed for user
		uint256 _liquidateDebtAmount = _getEffectiveDebtReducedFor(msg.sender, _debtAmount);

		address _controller = controller;
		IControllerZooMinimal(_controller).controlBeforeLiquidate(address(this), msg.sender, _liquidateDebtAmount);

		_selfLiquidate(msg.sender, _liquidateDebtAmount);

		IControllerZooMinimal(_controller).controlAfterLiquidate(address(this), msg.sender, _liquidateDebtAmount);
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
		_checkNotPaused();
		if (_debtAmount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		address _controller = controller;
		IControllerZooMinimal(_controller).controlBeforeMint(address(this), msg.sender, _debtAmount);

		_mint(msg.sender, _debtAmount);

		IControllerZooMinimal(_controller).controlAfterMint(address(this), msg.sender, _debtAmount);
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
		if (_debtAmount == 0) {
			revert ZeroValue();
		}
		_distribute();
		_update(msg.sender);

		// Computes effective debt reduction allowed for user
		uint256 _burnDebtAmount = _getEffectiveDebtReducedFor(msg.sender, _debtAmount);

		address _controller = controller;
		IControllerZooMinimal(_controller).controlBeforeBurn(address(this), msg.sender, _burnDebtAmount);

		_burn(msg.sender, _burnDebtAmount);

		IControllerZooMinimal(_controller).controlAfterBurn(address(this), msg.sender, _burnDebtAmount);
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
	function sync(address _user) external {
		_onlyController();
		_distribute();
		_update(_user);
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

		uint256 _earnedYield = ((_accumulatedYieldWeight - _userInfo.lastAccumulatedYieldWeight) *
			_userTotalDeposited) / FIXED_POINT_SCALAR;

		int256 _userTotalDebt = _userInfo.totalDebt - SafeCast.toInt256(_earnedYield);
		return (_userTotalDeposited, _userTotalDebt);
	}

	function _deposit(address _user, uint256 _collatAmount) internal {
		// Transfers tokens from user and deposits into the vault manager
		TokenUtils.safeTransferFrom(collatToken, _user, vaultManager, _collatAmount);
		IVaultManagerMinimal(vaultManager).deposit(_collatAmount);

		// Increases deposit for user
		UserInfo storage _userInfo = _userInfos[_user];
		_userInfo.totalDeposited += _collatAmount;
		totalDeposited += _collatAmount;

		emit TokensDeposited(_user, _collatAmount);
	}

	function _withdraw(address _user, uint256 _collatAmount) internal {
		// Decreases deposit for user
		UserInfo storage _userInfo = _userInfos[_user];
		_userInfo.totalDeposited -= _collatAmount;
		totalDeposited -= _collatAmount;

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

		// Reduces platform debt
		totalDebt -= SafeCast.toInt256(_debtAmount);

		// Transfers liquidated native tokens to the keeper
		_distributeToKeeper(_nativeAmount);

		emit TokensLiquidated(_user, _debtAmount);
	}

	function _mint(address _user, uint256 _debtAmount) internal {
		// Increases debt for user
		_increaseDebtFor(_user, SafeCast.toInt256(_debtAmount));

		// Checks max debt breached
		int256 _totalDebt = totalDebt + SafeCast.toInt256(_debtAmount);
		if (_totalDebt > maxDebt) {
			revert MaxDebtBreached();
		}
		totalDebt = _totalDebt;
		// Mints debt tokens to user
		TokenUtils.safeMint(debtToken, _user, _debtAmount);

		emit TokensMinted(_user, _debtAmount);
	}

	function _burn(address _user, uint256 _debtAmount) internal {
		// Burns debt tokens from user

		TokenUtils.safeBurnFrom(debtToken, _user, _debtAmount);
		totalDebt -= SafeCast.toInt256(_debtAmount);

		// Decreases debt for user
		_increaseDebtFor(_user, -SafeCast.toInt256(_debtAmount));

		emit TokensBurned(_user, _debtAmount);
	}

	function _normalizeNativeToDebt(uint256 _amount) internal view returns (uint256) {
		return _amount * conversionFactor;
	}

	function _normalizeDebtToNative(uint256 _amount) internal view returns (uint256) {
		return _amount / conversionFactor;
	}

	function _increaseDebtFor(address _owner, int256 _debtAmount) internal {
		UserInfo storage _userInfo = _userInfos[_owner];
		_userInfo.totalDebt += _debtAmount;
	}

	function _getEffectiveDebtReducedFor(address _owner, uint256 _wishedDebtReducedAmount)
		internal
		view
		returns (uint256)
	{
		UserInfo storage _userInfo = _userInfos[_owner];

		int256 _userDebt = _userInfo.totalDebt;
		// Dont attempt to reduce if no debt
		if (_userDebt <= 0) {
			revert NoPositiveDebt();
		}

		// Dont attempt to reduce more than debt
		uint256 _effectiveDebtReduced = Math.min(_wishedDebtReducedAmount, uint256(_userDebt));

		return _effectiveDebtReduced;
	}

	function _update(address _owner) internal {
		UserInfo storage _userInfo = _userInfos[_owner];

		uint256 _earnedYield = ((_accumulatedYieldWeight - _userInfo.lastAccumulatedYieldWeight) *
			_userInfo.totalDeposited) / FIXED_POINT_SCALAR;

		_userInfo.totalDebt -= SafeCast.toInt256(_earnedYield);
		_userInfo.lastAccumulatedYieldWeight = _accumulatedYieldWeight;
	}

	function _distribute() internal {
		uint256 _harvestedNativeAmount = TokenUtils.safeBalanceOf(nativeToken, address(this));

		if (_harvestedNativeAmount > 0) {
			// Repays users' debt
			uint256 _repaidDebtAmount = _normalizeNativeToDebt(_harvestedNativeAmount);
			uint256 _weight = (_repaidDebtAmount * FIXED_POINT_SCALAR) / totalDeposited;
			_accumulatedYieldWeight += _weight;

			// Reduces platform debt
			totalDebt -= SafeCast.toInt256(_repaidDebtAmount);

			// Distributes harvest to keeper
			_distributeToKeeper(_harvestedNativeAmount);
		}

		emit HarvestRewardDistributed(_harvestedNativeAmount);
	}

	function _distributeToKeeper(uint256 _nativeAmount) internal {
		address _keeper = keeper;
		TokenUtils.safeTransfer(nativeToken, _keeper, _nativeAmount);
		IERC20TokenReceiver(_keeper).onERC20Received(nativeToken, _nativeAmount);
	}

	function _onlyController() internal view {
		if (controller != msg.sender) {
			revert OnlyControllerAllowed();
		}
	}

	event TokensDeposited(address indexed account, uint256 amount);

	event TokensWithdrawn(address indexed account, uint256 amount);

	event TokensMinted(address indexed account, uint256 amount);

	event TokensBurned(address indexed account, uint256 amount);

	event TokensLiquidated(address indexed account, uint256 requestedAmount);

	event ControllerUpdated(address controller);

	event KeeperUpdated(address keeper);

	event VaultManagerUpdated(address vaultManager);

	event MaxDebtUpdated(int256 maxDebtAmount);

	event HarvestRewardDistributed(uint256 amount);

	error MaxDebtBreached();

	error NoPositiveDebt();

	error OnlyControllerAllowed();
}

