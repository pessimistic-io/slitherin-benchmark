// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "./ERC20.sol";
import { ERC4626, FixedPointMathLib, SafeERC20, IWETH, Accounting } from "./ERC4626.sol";
import { BatchedWithdraw } from "./BatchedWithdraw.sol";
import { Address } from "./Address.sol";
import { EAction } from "./Structs.sol";
import { VaultType } from "./Structs.sol";
import { SafeETH } from "./SafeETH.sol";

// import "hardhat/console.sol";

abstract contract SectorBase is BatchedWithdraw, ERC4626 {
	using FixedPointMathLib for uint256;
	using SafeERC20 for ERC20;

	VaultType public constant vaultType = VaultType.Aggregator;

	uint256 public totalChildHoldings;
	uint256 public floatAmnt; // amount of underlying tracked in vault
	uint256 public maxHarvestInterval; // emergency redeem is enabled after this time

	constructor() {
		lastHarvestTimestamp = block.timestamp;
	}

	function setMaxHarvestInterval(uint256 maxHarvestInterval_) public onlyOwner {
		maxHarvestInterval = maxHarvestInterval_;
		emit SetMaxHarvestInterval(maxHarvestInterval);
	}

	function withdraw(
		uint256,
		address,
		address
	) public pure virtual override returns (uint256) {
		revert NotImplemented();
	}

	function redeem(
		uint256,
		address receiver,
		address
	) public virtual override returns (uint256 amountOut) {
		return redeem(receiver);
	}

	function redeemNative(address receiver) public virtual returns (uint256 amountOut) {
		if (!useNativeAsset) revert NotNativeAsset();
		uint256 shares;
		(amountOut, shares) = _redeem(msg.sender);

		beforeWithdraw(amountOut, shares);
		_burn(address(this), shares);

		emit Withdraw(msg.sender, receiver, msg.sender, amountOut, shares);

		IWETH(address(asset)).withdraw(amountOut);
		SafeETH.safeTransferETH(receiver, amountOut);
	}

	function redeem(address receiver) public virtual returns (uint256 amountOut) {
		uint256 shares;
		(amountOut, shares) = _redeem(msg.sender);

		beforeWithdraw(amountOut, shares);
		_burn(address(this), shares);

		emit Withdraw(msg.sender, receiver, msg.sender, amountOut, shares);
		asset.safeTransfer(receiver, amountOut);
	}

	/// @dev safest UI method
	function redeem() public virtual returns (uint256 amountOut) {
		return redeem(msg.sender);
	}

	/// @dev safest UI method
	function redeemNative() public virtual returns (uint256 amountOut) {
		return redeemNative(msg.sender);
	}

	function _harvest(uint256 currentChildHoldings) internal {
		// withdrawFromStrategies should be called prior to harvest to ensure this tx doesn't revert
		// pendingWithdraw may be larger than the actual withdrawable amount if vault sufferred losses
		// since the previous harvest

		uint256 tvl = currentChildHoldings + floatAmnt;
		uint256 _totalSupply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

		/// this is actually a max amount that can be withdrawn given current tvl
		/// actual withdraw amount may be slightly less if there are stale withdraw requests
		uint256 pendingWithdraw = requestedRedeem.mulDivDown(tvl, _totalSupply);
		if (floatAmnt < pendingWithdraw) revert NotEnoughtFloat();

		uint256 profit = currentChildHoldings > totalChildHoldings
			? currentChildHoldings - totalChildHoldings
			: 0;

		uint256 timestamp = block.timestamp;

		// totalChildHoldings need to be updated before fees computation
		totalChildHoldings = currentChildHoldings;

		// PROCESS VAULT FEES
		uint256 _performanceFee = profit == 0 ? 0 : (profit * performanceFee) / 1e18;
		uint256 _managementFee = managementFee == 0
			? 0
			: (managementFee * tvl * (timestamp - lastHarvestTimestamp)) / 1e18 / 365 days;

		uint256 totalFees = _performanceFee + _managementFee;
		uint256 feeShares;

		if (totalFees > 0) {
			// this results in more accurate accounting considering dilution
			feeShares = totalFees.mulDivDown(_totalSupply, tvl - totalFees);
			_mint(treasury, feeShares);
		}

		emit Harvest(treasury, profit, _performanceFee, _managementFee, feeShares, tvl);

		// this enables withdrawals requested prior to this timestamp
		lastHarvestTimestamp = timestamp;
		_processRedeem();
	}

	/// @notice this method allows an arbitrary method to be called by the owner in case of emergency
	/// owner must be a timelock contract in order to allow users to redeem funds in case they suspect
	/// this action to be malicious
	function emergencyAction(EAction[] calldata actions) public payable onlyOwner {
		uint256 l = actions.length;
		for (uint256 i; i < l; ++i) {
			address target = actions[i].target;
			bytes memory data = actions[i].data;
			(bool success, ) = target.call{ value: actions[i].value }(data);
			require(success, "emergencyAction failed");
			emit EmergencyAction(target, data);
		}
	}

	function _checkSlippage(
		uint256 expectedValue,
		uint256 actualValue,
		uint256 maxDelta
	) internal pure {
		uint256 delta = expectedValue > actualValue
			? expectedValue - actualValue
			: actualValue - expectedValue;
		if (delta > maxDelta) revert SlippageExceeded();
	}

	function totalAssets() public view virtual override(Accounting, ERC4626) returns (uint256) {
		return floatAmnt + totalChildHoldings;
	}

	/// INTERFACE UTILS

	/// @dev returns a cached value used for withdrawals
	function underlyingBalance(address user) public view returns (uint256) {
		uint256 shares = balanceOf(user);
		return convertToAssets(shares);
	}

	function getUpdatedUnderlyingBalance(address user) public view returns (uint256) {
		uint256 shares = balanceOf(user);
		return convertToAssets(shares);
	}

	function underlyingDecimals() public view returns (uint8) {
		return asset.decimals();
	}

	function underlying() public view returns (address) {
		return address(asset);
	}

	/// OVERRIDES
	function decimals() public view override(ERC20, ERC4626) returns (uint8) {
		return asset.decimals();
	}

	function afterDeposit(uint256 assets, uint256) internal override {
		if (block.timestamp - lastHarvestTimestamp > maxHarvestInterval)
			revert EmergencyRedeemEnabled();

		floatAmnt += assets;
	}

	function beforeWithdraw(uint256 assets, uint256) internal override {
		// this check prevents withdrawing more underlying from the vault then
		// what we need to keep to honor withdrawals
		uint256 pendingWithdraw = convertToAssets(pendingRedeem);
		if (floatAmnt < assets + pendingWithdraw) revert NotEnoughtFloat();
		floatAmnt -= assets;
	}

	event RegisterDeposit(uint256 total);
	event EmergencyWithdraw(address vault, address client, uint256 shares);
	event EmergencyAction(address target, bytes callData);
	event Harvest(
		address indexed treasury,
		uint256 underlyingProfit,
		uint256 performanceFee,
		uint256 managementFee,
		uint256 sharesFees,
		uint256 tvl
	);
	event SetMaxHarvestInterval(uint256 maxHarvestInterval);

	error RecentHarvest();
	error MaxRedeemNotZero();
	error NotEnoughtFloat();
	error WrongUnderlying();
	error SlippageExceeded();
	error StrategyExists();
	error StrategyNotFound();
	error MissingDepositValue();
	error EmergencyRedeemEnabled();
}

