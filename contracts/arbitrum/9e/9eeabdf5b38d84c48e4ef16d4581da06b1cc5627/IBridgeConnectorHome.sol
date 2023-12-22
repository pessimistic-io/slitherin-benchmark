// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBridgeConnectorHome {
	function bridgeFunds(
		uint256 _amount,
		uint256 _chainId,
		uint256 _minAmount,
		bytes calldata _bridgeData
	) external payable;

	function estimateBridgeCost(
		uint256 _chainId,
		uint256 _amount
	) external view returns (uint256 gasEstimation);

	function addChain(
		uint256 _chainId,
		address _allocator,
		address _remoteConnector,
		bytes calldata _params
	) external;
}

