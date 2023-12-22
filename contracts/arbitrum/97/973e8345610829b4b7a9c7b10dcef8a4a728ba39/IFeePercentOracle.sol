// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

interface IFeePercentOracle {
	/**
	 * @notice Sets the values for {feepercent} and {decimals}.
	 * {_feepercent=4, _decimals=2} -> {4 / 10 ** 2} -> 4%
	 * @dev Must be owner.
	 * @param _feepercent the new percentage number
	 * @param _decimals the new decimal of the percentage
	 */
	function setValues(uint120 _feepercent, uint8 _decimals) external;

	/**
	 * @notice Returns the fee percent and recipient cut for a given amount.
	 * @param amount The amount to calculate the fee for.
	 * @return funCut The fee percent.
	 * @return recipCut The recipient cut.
	 */
	function getFee(uint256 amount) external view returns (uint256, uint256);
}

