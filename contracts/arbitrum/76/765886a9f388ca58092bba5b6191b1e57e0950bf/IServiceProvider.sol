// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ISubscriptionRegistry.sol";

interface IServiceProvider  {

	function serviceProvider() external view returns (address);
	function subscriptionRegistry() external view returns (ISubscriptionRegistry);
}
