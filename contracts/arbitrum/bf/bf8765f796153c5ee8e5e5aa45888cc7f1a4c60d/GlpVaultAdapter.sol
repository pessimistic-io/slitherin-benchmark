// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { Math } from "./Math.sol";

import { IRewardRouterV2 } from "./IRewardRouterV2.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { IVaultAdapter } from "./IVaultAdapter.sol";

import { PausableAccessControl } from "./PausableAccessControl.sol";

import { TokenUtils } from "./TokenUtils.sol";
import "./Errors.sol";

/// @title GlpVaultAdapter
/// @author Koala Money
///
/// @notice A vault adapter implementation which wraps staking pools.
contract GlpVaultAdapter is IVaultAdapter, PausableAccessControl {
	/// @notice The identifier of the role that sends funds and execute the onERC20Received callback
	bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER");

	address public immutable sGLP;

	address public immutable usdc;

	address public immutable rewardRouter;

	/// @notice The address which has withdraw control over this contract.
	address public immutable master;

	constructor(
		address _sGLP,
		address _usdc,
		address _rewardRouter,
		address _master
	) {
		sGLP = _sGLP;
		usdc = _usdc;
		rewardRouter = _rewardRouter;
		master = _master;
	}

	/// @inheritdoc IVaultAdapter
	function deposit(uint256 _amount) external override {
		_onlyMaster();
		// Nothing to do here

		emit GaugeDeposited(_amount);
	}

	/// @inheritdoc IVaultAdapter
	function withdraw(address _recipient, uint256 _amount) external override {
		_onlyMaster();

		TokenUtils.safeTransfer(sGLP, _recipient, _amount);

		emit GaugeWithdrawn(_recipient, _amount);
	}

	/// @notice Harvests rewards from the underlying masterchef.
	///
	/// @notice Reverts if caller does not have the harvester role.
	function harvest(address _recipient) external {
		_onlyHarvester();

		uint256 _harvestedAmount = TokenUtils.safeBalanceOf(usdc, address(this));
		if (_harvestedAmount > 0) {
			TokenUtils.safeTransfer(usdc, _recipient, _harvestedAmount);
		}

		emit GaugeHarvested(_recipient, _harvestedAmount);
	}

	/// @notice Allows the harvester to withdraw rewards in order to convert them into lp token and inject them back into the vault.
	///
	/// @notice Reverts if the caller does not have the harvester role.
	/// @notice Reverts if the caller tries to withdraw trisolaris lp token.
	function withdrawRewards(
		address _token,
		address _recipient,
		uint256 _amount
	) external {
		_onlyHarvester();
		// Can not withdraw staking token or reward token
		if (sGLP == _token) {
			revert TokenWithdrawForbidden();
		}
		TokenUtils.safeTransfer(_token, _recipient, _amount);
	}

	function claim() external {
		_onlyHarvester();

		IRewardRouterV2(rewardRouter).handleRewards(true, true, true, true, true, true, false);
	}

	/// @notice Check that the caller has the harvester role.
	function _onlyMaster() internal view {
		if (master != msg.sender) {
			revert OnlyMasterAllowed();
		}
	}

	/// @notice Check that the caller has the harvester role.
	function _onlyHarvester() internal view {
		if (!hasRole(HARVESTER_ROLE, msg.sender)) {
			revert OnlyHarvesterAllowed();
		}
	}

	/// @notice Emitted when tokens are deposited into the gauge.
	///
	/// @param amount The amount of tokens deposited.
	event GaugeDeposited(uint256 amount);

	/// @notice Emitted when token are withdrawn from the gauge.
	///
	/// @param recipient The address of the recipient that gets the funds withdrawn
	/// @param amount The amount of tokens withdrawn.
	event GaugeWithdrawn(address recipient, uint256 amount);

	/// @notice Emitted when rewards are harvested from the gauge.
	///
	/// @param recipient The address of the recipient that gets the funds harvested
	/// @param amount The amount of tokens harvested.
	event GaugeHarvested(address recipient, uint256 amount);

	/// @notice Indicates that the caller is missing the harvester role.
	error OnlyHarvesterAllowed();

	/// @notice Indicates that the caller is not the master.
	error OnlyMasterAllowed();

	/// @notice Indicates that the caller is trying to withdraw the vault token.
	error TokenWithdrawForbidden();
}

