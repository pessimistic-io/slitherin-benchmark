// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IVault {
	function buyUSDG(address _token, address _receiver) external returns (uint256);

	function sellUSDG(address _token, address _receiver) external returns (uint256);

	function swap(
		address _tokenIn,
		address _tokenOut,
		address _receiver
	) external returns (uint256);

	function getMaxPrice(address _token) external view returns (uint256);

	function getMinPrice(address _token) external view returns (uint256);

	function adjustForDecimals(
		uint256 _amount,
		address _tokenDiv,
		address _tokenMul
	) external view returns (uint256);

	function mintBurnFeeBasisPoints() external view returns (uint256);

	function taxBasisPoints() external view returns (uint256);

	function stableTokens(address) external view returns (bool);

	function stableSwapFeeBasisPoints() external view returns (uint256);

	function swapFeeBasisPoints() external view returns (uint256);

	function stableTaxBasisPoints() external view returns (uint256);

	function hasDynamicFees() external view returns (bool);

	function usdgAmounts(address _token) external view returns (uint256);

	function getTargetUsdgAmount(address _token) external view returns (uint256);
}


