// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { ERC20 } from "./ERC20.sol";
import { Math } from "./Math.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import { IVaultAdapter } from "./IVaultAdapter.sol";
import { IERC20TokenReceiver } from "./IERC20TokenReceiver.sol";

import { PausableAccessControl } from "./PausableAccessControl.sol";
import { TokenUtils } from "./TokenUtils.sol";
import "./Errors.sol";

contract VaultManager is PausableAccessControl, ReentrancyGuard {
	/// @notice A structure to store the informations related to a vault.
	struct Vault {
		/// @notice The address of the vault adapter.
		address adapter;
		/// @notice The total amount deposited into the vault.
		uint256 totalDeposited;
	}

	/// @notice The identifier of the role that sends funds and execute the onERC20Received callback
	bytes32 public constant SOURCE_ROLE = keccak256("SOURCE");

	/// @notice The identifier of the role that sends funds and execute the onERC20Received callback
	bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR");

	/// @notice Gets the address of the underlying token managed by the vault manager.
	address public immutable sGLP;

	address public immutable fsGLP;

	/// @notice Gets the address of the reward token managed by the vault manager.
	address public immutable usdc;

	/// @notice Gets the address of the contract that receives the harvested rewards.
	address public rewardReceiver;

	/// @notice Gets the required amount of tokens deposited before they are automatically flushed into the active vault.
	uint256 public flushThreshold;

	/// @notice Gets the number of vaults in the vault list.
	uint256 public vaultCount;

	/// @notice Associates a unique number with a vault.
	mapping(uint256 => Vault) private _vaults;

	constructor(
		address _sGLP,
		address _fsGLP,
		address _usdc,
		address _rewardReceiver
	) {
		sGLP = _sGLP;
		fsGLP = _fsGLP;
		usdc = _usdc;
		rewardReceiver = _rewardReceiver;
	}

	receive() external payable {}

	/// @notice Sets the address of the active vault adapter.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	/// @notice Reverts with an {UnsupportedVaultToken} error if the adapter underlying token differs from vault manager underlying token.
	///
	/// @notice Emits a {ActiveVaultUpdated} event.
	///
	/// @param _vaultAdapter the adapter for the vault the system will migrate to.
	function setActiveVault(address _vaultAdapter) external {
		_onlyAdmin();

		// Checks if vault supports the underlying token
		if (IVaultAdapter(_vaultAdapter).token() != sGLP) {
			revert UnsupportedVaultToken();
		}

		uint256 _vaultCount = vaultCount;
		_vaults[_vaultCount] = Vault({ adapter: _vaultAdapter, totalDeposited: 0 });
		vaultCount = _vaultCount + 1;

		emit ActiveVaultUpdated(_vaultAdapter);
	}

	/// @notice Sets the rewardReceiver.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	/// @notice Reverts with an {ZeroAddress} error if the rewardReceiver is the 0 address.
	///
	/// @notice Emits a {RewardReceiverUpdated} event.
	///
	/// @param _rewardReceiver the address of the rewardReceiver that receives the rewards.
	function setRewardReceiver(address _rewardReceiver) external {
		_onlyAdmin();
		if (_rewardReceiver == address(0)) {
			revert ZeroAddress();
		}

		rewardReceiver = _rewardReceiver;

		emit RewardReceiverUpdated(_rewardReceiver);
	}

	/// @notice Sets the flush threshold.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	///
	/// @notice Emits a {FlushThresholdUpdated} event.
	///
	/// @param _flushThreshold the new flushThreshold.
	function setFlushThreshold(uint256 _flushThreshold) external {
		_onlyAdmin();

		flushThreshold = _flushThreshold;

		emit FlushThresholdUpdated(_flushThreshold);
	}

	/// @notice Deposits underlying tokens into the vault.
	///
	/// @notice Reverts with an {ContractPaused} error if the contract is in pause state.
	///
	/// @notice Emits a {TokensDeposited} event.
	///
	/// @param _amount The amount of underlying tokens to deposit.
	function deposit(uint256 _amount) external nonReentrant {
		_onlySource();
		_checkNotPaused();

		if (_amount == 0) {
			revert ZeroValue();
		}

		uint256 _underlyingReserve = TokenUtils.safeBalanceOf(fsGLP, address(this));
		if (_underlyingReserve > flushThreshold) {
			_depositToVault(vaultCount - 1, _underlyingReserve);
		}

		emit TokensDeposited(msg.sender, _amount);
	}

	/// @notice Withdraws `_amount` of underlying tokens and send them to `_recipient`.
	///
	/// @notice Emits a {TokensWithdrawn} event.
	///
	/// @param _recipient The address of the recipient of the funds.
	/// @param _amount The amount of tokens to withdraw.
	function withdraw(address _recipient, uint256 _amount) external nonReentrant {
		_onlySource();
		if (_recipient == address(0)) {
			revert ZeroAddress();
		}
		if (_amount == 0) {
			revert ZeroValue();
		}

		uint256 _underlyingReserve = TokenUtils.safeBalanceOf(fsGLP, address(this));

		uint256 _amountLeftToWithdraw = _amount;
		if (_amount > _underlyingReserve) {
			uint256 _missingReserveAmount = _amount - _underlyingReserve;
			_amountLeftToWithdraw = _underlyingReserve;
			_withdrawFromVault(vaultCount - 1, _recipient, _missingReserveAmount);
		}
		if (_amountLeftToWithdraw > 0) {
			TokenUtils.safeTransfer(sGLP, _recipient, _amountLeftToWithdraw);
		}
		emit TokensWithdrawn(_recipient, _amount);
	}

	/// @notice Harvests yield from a vault and transfer the harvested amount to the rewardReceiver.
	///
	/// @notice Reverts with an {OutOfBoundsArgument} error if the vault id argument is out of bounds.
	/// @notice Reverts with an {NothingHarvested} error if the harvested amount is 0.
	///
	/// @notice Emits a {FundsHarvested} event.
	///
	/// @param _vaultId The identifier of the vault to harvest from.
	function harvest(uint256 _vaultId) external nonReentrant {
		if (_vaultId >= vaultCount) {
			revert OutOfBoundsArgument();
		}

		IVaultAdapter(_vaults[_vaultId].adapter).harvest(address(this));
	}

	function distribute() external nonReentrant returns (uint256) {
		_onlyDistributor();
		uint256 _distributeAmount = TokenUtils.safeBalanceOf(usdc, address(this));
		if (_distributeAmount == 0) {
			revert NothingHarvested();
		}
		_distributeToRewardReceiver(_distributeAmount);

		emit FundsHarvested(_distributeAmount);

		return _distributeAmount;
	}

	/// @notice Flushes all funds from the contract into the active vault.
	///
	/// @notice Reverts with an {ContractPaused} error if the contract is in pause state.
	///
	/// @notice Emits a {FundsFlushed} event.
	///
	/// @notice Reverts if the contract is in pause state.
	function flush() external nonReentrant {
		_checkNotPaused();

		uint256 _underlyingReserve = TokenUtils.safeBalanceOf(sGLP, address(this));
		if (_underlyingReserve == 0) {
			revert NothingFlushed();
		}
		_depositToVault(vaultCount - 1, _underlyingReserve);
	}

	/// @notice Recalls an amount of deposited funds from a vault to this contract.
	///
	/// @notice Reverts with an {Unauthorized} error if all the following conditions are true:
	/// @notice - Contract is not in pause state.
	/// @notice - Caller is missing the admin role.
	/// @notice - `_vaultId` is the id of the active vault.
	/// @notice Reverts with an {OutOfBoundsArgument} error if the vault id argument is out of bounds.
	///
	/// @notice Emits a {FundsRecalled} event.
	///
	/// @param _vaultId The identifier of the vault funds are recalled from.
	/// @param _amount The amount of tokens recalled from the vault.
	function recall(uint256 _vaultId, uint256 _amount) external nonReentrant {
		_recall(_vaultId, _amount);
	}

	/// @notice Recalls all the deposited funds from a vault to this contract.
	function recallAll(uint256 _vaultId) external nonReentrant returns (uint256) {
		uint256 _totalDeposited = _vaults[_vaultId].totalDeposited;
		_recall(_vaultId, _totalDeposited);
		return _totalDeposited;
	}

	/// @notice Gets the address of the adapter and the total amount deposited for the vault number  `_vaultId`.
	///
	/// @param _vaultId the identifier of the vault to query.
	///
	/// @return The address of the vault adapter.
	/// @return The total amount of deposited tokens.
	function vault(uint256 _vaultId) external view returns (address, uint256) {
		Vault storage _vault = _vaults[_vaultId];
		return (_vault.adapter, _vault.totalDeposited);
	}

	function _recall(uint256 _vaultId, uint256 _amount) internal {
		if (!paused && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && _vaultId == vaultCount - 1) {
			revert Unauthorized();
		}
		if (_vaultId >= vaultCount) {
			revert OutOfBoundsArgument();
		}
		if (_amount == 0) {
			revert NothingRecalled();
		}

		_withdrawFromVault(_vaultId, address(this), _amount);

		emit FundsRecalled(_vaultId, _amount);
	}

	function _distributeToRewardReceiver(uint256 _amount) internal {
		address _rewardReceiver = rewardReceiver;
		TokenUtils.safeTransfer(usdc, _rewardReceiver, _amount);
		IERC20TokenReceiver(_rewardReceiver).onERC20Received(usdc, _amount);
	}

	function _withdrawFromVault(
		uint256 _vaultId,
		address _recipient,
		uint256 _amount
	) internal {
		// Decreases vault deposit
		Vault storage _vault = _vaults[_vaultId];
		_vault.totalDeposited -= _amount;
		// Withdraws from vault to reserve
		IVaultAdapter(_vault.adapter).withdraw(_recipient, _amount);
	}

	function _depositToVault(uint256 _vaultId, uint256 _amount) internal {
		// Increases vault deposit
		Vault storage _vault = _vaults[_vaultId];
		_vault.totalDeposited += _amount;
		// Deposits from reserve to vault
		address _adapter = _vault.adapter;
		TokenUtils.safeTransfer(sGLP, _adapter, _amount);
		IVaultAdapter(_adapter).deposit(_amount);

		emit FundsFlushed(_amount);
	}

	function _onlySource() internal view {
		if (!hasRole(SOURCE_ROLE, msg.sender)) {
			revert OnlySourceAllowed();
		}
	}

	function _onlyDistributor() internal view {
		if (!hasRole(DISTRIBUTOR_ROLE, msg.sender)) {
			revert OnlyDistributorAllowed();
		}
	}

	event TokensDeposited(address recipient, uint256 amount);

	event TokensWithdrawn(address recipient, uint256 amount);

	event ActiveVaultUpdated(address adapter);

	event RewardReceiverUpdated(address rewardReceiver);

	event FundsHarvested(uint256 harvestedAmount);

	event FundsRecalled(uint256 indexed vaultId, uint256 amount);

	event FundsFlushed(uint256 flushedAmount);

	event FlushThresholdUpdated(uint256 flushThreshold);

	error UnsupportedVaultToken();

	error NothingFlushed();

	error NothingRecalled();

	error NothingHarvested();

	error OnlySourceAllowed();

	error OnlyDistributorAllowed();
}

