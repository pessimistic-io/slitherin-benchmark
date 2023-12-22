// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IRootVault.sol";
import "./IBridgeAdapter.sol";

contract FeeClaimer
{
	using SafeERC20 for IERC20;

	constructor()
	{
	}

	function claimFeeAndBridge(IRootVault rootVault, IBridgeAdapter bridgeAdapter, uint256 shares) external
	{
		IERC20 token = IERC20(rootVault.asset());
		if (rootVault.balanceOf(msg.sender) < shares)
		{
			rootVault.recomputePricePerTokenAndHarvestFee();
		}

		rootVault.transferFrom(msg.sender, address(this), shares);
		uint256 value = rootVault.redeem(shares, address(this));

		token.safeIncreaseAllowance(address(bridgeAdapter), value);
		bridgeAdapter.sendAssets(value, msg.sender, 0);
	}

	function getTotalFees(IRootVault rootVault, address claimer) external returns (uint256 shares)
	{
		rootVault.recomputePricePerTokenAndHarvestFee();

		return rootVault.balanceOf(claimer);
	}
}
