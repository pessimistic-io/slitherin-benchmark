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

	/// @notice Gets the address of the underlying token managed by the vault manager.
	address public immutable sGLP;

	address public immutable fsGLP;

	/// @notice Gets the address of the reward token managed by the vault manager.
	address public immutable usdc;

	/// @notice Gets the address of the contract that receives the harvested rewards.
	address public harvester;

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
		address _harvester
	) {
		sGLP = _sGLP;
		fsGLP = _fsGLP;
		usdc = _usdc;
		harvester = _harvester;
	}

	/// @notice Sets the address of the active vault adapter.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	/// @notice Reverts with an {UnsupportedsGLP} error if the adapter underlying token differs from vault manager underlying token.
	///
	/// @notice Emits a {ActiveVaultUpdated} event.
	///
	/// @param _vaultAdapter the adapter for the vault the system will migrate to.
	function setActiveVault(address _vaultAdapter) external {
		_onlyAdmin();

		// Checks if vault supports the underlying token
		if (IVaultAdapter(_vaultAdapter).token() != sGLP) {
			revert UnsupportedsGLP();
		}

		uint256 _vaultCount = vaultCount;
		_vaults[_vaultCount] = Vault({ adapter: _vaultAdapter, totalDeposited: 0 });
		vaultCount = _vaultCount + 1;

		emit ActiveVaultUpdated(_vaultAdapter);
	}

	/// @notice Sets the harvester.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	/// @notice Reverts with an {ZeroAddress} error if the harvester is the 0 address.
	///
	/// @notice Emits a {HarvesterUpdated} event.
	///
	/// @param _harvester the address of the harvester that receives the rewards.
	function setHarvester(address _harvester) external {
		_onlyAdmin();
		if (_harvester == address(0)) {
			revert ZeroAddress();
		}

		harvester = _harvester;

		emit HarvesterUpdated(_harvester);
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

	/// @notice Harvests yield from a vault and transfer the harvested amount to the harvester.
	///
	/// @notice Reverts with an {OutOfBoundsArgument} error if the vault id argument is out of bounds.
	/// @notice Reverts with an {NothingHarvested} error if the harvested amount is 0.
	///
	/// @notice Emits a {FundsHarvested} event.
	///
	/// @param _vaultId The identifier of the vault to harvest from.
	///
	/// @return The amount of tokens harvested.
	function harvest(uint256 _vaultId) external nonReentrant returns (uint256) {
		if (_vaultId >= vaultCount) {
			revert OutOfBoundsArgument();
		}

		address _adapter = _vaults[_vaultId].adapter;
		IVaultAdapter(_adapter).harvest(address(this));

		uint256 _harvestedAmount = TokenUtils.safeBalanceOf(usdc, address(this));
		if (_harvestedAmount == 0) {
			revert NothingHarvested();
		}

		_distributeToHarvester(_harvestedAmount);

		emit FundsHarvested(_harvestedAmount);

		return _harvestedAmount;
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

	/// @notice Recalls an amount of funds from a vault.
	///
	/// @param _vaultId The identifier of the vault to recall funds from.
	/// @param _amount  The amount of funds to recall from the vault.
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

	function _distributeToHarvester(uint256 _amount) internal {
		address _harvester = harvester;
		TokenUtils.safeTransfer(usdc, _harvester, _amount);
		IERC20TokenReceiver(_harvester).onERC20Received(usdc, _amount);
	}

	/// @notice Pulls `_amount ` of tokens from vault `_vaultId`.
	///
	/// @param _vaultId The id of the vault to withdraw funds from.
	/// @param _recipient The beneficiary of the withdrawn funds.
	/// @param _amount The amount of funds to withdraw.
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

	/// @notice Flushes `_amount ` of tokens to vault `_vaultId`.
	///
	/// @param _vaultId The id of the vault to deposit funds to.
	/// @param _amount The amount of funds to deposit.
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

	/// @notice Check that the caller has the source role.
	function _onlySource() internal view {
		if (!hasRole(SOURCE_ROLE, msg.sender)) {
			revert OnlySourceAllowed();
		}
	}

	/// @notice Emitted when `amount` of underlying tokens are deposited into the vault and an equivalent amount of vault token is minted.
	///
	/// @param recipient The address of the account that receives the newly minted tokens.
	/// @param amount The amount of tokens deposited.
	event TokensDeposited(address recipient, uint256 amount);

	/// @notice Emitted when `amount` of tokens are burned and an equivalent amount of underlying tokens are transferred to `recipient`.
	///
	/// @param recipient The address of the beneficiary that receives the funds withdrawn.
	/// @param amount The amount of token burnt.
	event TokensWithdrawn(address recipient, uint256 amount);

	/// @notice Emitted when the active vault is updated.
	///
	/// @param adapter The address of the adapter.
	event ActiveVaultUpdated(address adapter);

	/// @notice Emitted when the harvester is updated.
	///
	/// @param harvester The address of the harvester.
	event HarvesterUpdated(address harvester);

	/// @notice Emitted when funds are harvested from the vault.
	///
	/// @param harvestedAmount The amount of funds harvested from the vault.
	event FundsHarvested(uint256 harvestedAmount);

	/// @notice Emitted when funds are recalled from an underlying vault.
	///
	/// @param vaultId The id of the vault.
	/// @param amount The amount of funds withdrawn from the vault.
	event FundsRecalled(uint256 indexed vaultId, uint256 amount);

	/// @notice Emitted when funds are flushed into the active vault.
	///
	/// @param flushedAmount The amount of funds flushed into the active vault.
	event FundsFlushed(uint256 flushedAmount);

	/// @notice Emitted when flush activator is updated.
	///
	/// @param flushThreshold The amount of tokens received before funds are automatically flush into the last vault.
	event FlushThresholdUpdated(uint256 flushThreshold);

	/// @notice Indicates that the vault token is not supported.
	error UnsupportedsGLP();

	/// @notice Indicates that a flush operation fails because there is nothing to flush.
	error NothingFlushed();

	/// @notice Indicates that a recall operation fails because there is nothing to recall.
	error NothingRecalled();

	/// @notice Indicates that an harvest operation fails because there is nothing to harvest.
	error NothingHarvested();

	/// @notice Indicates that the caller is missing the source role.
	error OnlySourceAllowed();
}

