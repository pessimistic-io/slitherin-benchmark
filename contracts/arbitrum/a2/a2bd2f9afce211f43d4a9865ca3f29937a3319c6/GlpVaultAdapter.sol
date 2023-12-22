// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { IRewardRouterV2 } from "./IRewardRouterV2.sol";
import { IVaultAdapter } from "./IVaultAdapter.sol";
import { IERC20TokenReceiver } from "./IERC20TokenReceiver.sol";

import { AdminAccessControl } from "./AdminAccessControl.sol";
import { TokenUtils } from "./TokenUtils.sol";
import "./Errors.sol";

/// @title GlpVaultAdapter
/// @author Koala Money
///
/// @notice A vault adapter implementation which wraps staking pools.
contract GlpVaultAdapter is IVaultAdapter, AdminAccessControl {
	/// @notice The identifier of the role that sends funds and execute the onERC20Received callback
	bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER");

	/// @notice The identifier of the role that sends funds and execute the onERC20Received callback
	bytes32 public constant SOURCE_ROLE = keccak256("SOURCE");

	address public immutable sGLP;

	address public immutable usdc;

	address public immutable rewardRouter;

	constructor(
		address _sGLP,
		address _usdc,
		address _rewardRouter
	) {
		sGLP = _sGLP;
		usdc = _usdc;
		rewardRouter = _rewardRouter;
	}

	/// @inheritdoc IVaultAdapter
	function deposit(uint256 _amount) external override {
		_onlySource();
		// Nothing to do here

		emit GaugeDeposited(_amount);
	}

	/// @inheritdoc IVaultAdapter
	function withdraw(address _recipient, uint256 _amount) external override {
		_onlySource();

		TokenUtils.safeTransfer(sGLP, _recipient, _amount);

		emit GaugeWithdrawn(_recipient, _amount);
	}

	/// @notice Harvests rewards from the underlying masterchef.
	///
	/// @notice Reverts if caller does not have the harvester role.
	function harvest(address _recipient) external override {
		_onlySource();

		uint256 _harvestedAmount = TokenUtils.safeBalanceOf(usdc, address(this));
		if (_harvestedAmount > 0) {
			TokenUtils.safeTransfer(usdc, _recipient, _harvestedAmount);
		}

		emit GaugeHarvested(_recipient, _harvestedAmount);
	}

	function token() external view override returns (address) {
		return sGLP;
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
	function _onlySource() internal view {
		if (!hasRole(SOURCE_ROLE, msg.sender)) {
			revert OnlySourceAllowed();
		}
	}

	/// @notice Check that the caller has the harvester role.
	function _onlyHarvester() internal view {
		if (!hasRole(HARVESTER_ROLE, msg.sender)) {
			revert OnlyHarvesterAllowed();
		}
	}

	/// @notice Emitted when the reward receiver address is updated.
	///
	/// @param rewardReceiver The address of the reward receiver.
	event RewardReceiverUpdated(address rewardReceiver);

	/// @notice Emitted when tokens are deposited into the gauge.
	///
	/// @param amount The amount of tokens deposited.
	event GaugeDeposited(uint256 amount);

	/// @notice Emitted when token are withdrawn from the gauge.
	///
	/// @param recipient The address of the recipient that gets the funds withdrawn.
	/// @param amount The amount of tokens withdrawn.
	event GaugeWithdrawn(address recipient, uint256 amount);

	/// @notice Emitted when rewards are harvested from the gauge.
	///
	/// @param recipient The address of the recipient that gets the funds harvested.
	/// @param amount The amount of tokens harvested.
	event GaugeHarvested(address recipient, uint256 amount);

	/// @notice Indicates that the caller is missing the harvester role.
	error OnlyHarvesterAllowed();

	/// @notice Indicates that the caller is missing the source role.
	error OnlySourceAllowed();

	/// @notice Indicates that the caller is trying to withdraw the vault token.
	error TokenWithdrawForbidden();
}

