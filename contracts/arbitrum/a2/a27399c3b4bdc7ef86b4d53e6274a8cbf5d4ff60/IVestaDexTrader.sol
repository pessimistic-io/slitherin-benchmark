// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { ManualExchange } from "./TradingModel.sol";

interface IVestaDexTrader {
	error InvalidTraderSelector();
	error TraderFailed(address trader, bytes returnedCallData);
	error FailedToReceiveExactAmountOut(uint256 minimumAmount, uint256 receivedAmount);
	error TraderFailedMaxAmountInExceeded(
		uint256 maximumAmountIn,
		uint256 requestedAmountIn
	);
	error RoutingNotFound();
	error EmptyRequest();

	event TraderRegistered(address indexed trader, bytes16 selector);
	event TraderRemoved(address indexed trader);
	event RouteUpdated(address indexed tokenIn, address indexed tokenOut);
	event SwapExecuted(
		address indexed executor,
		address indexed receiver,
		address[2] tokenInOut,
		uint256[2] amountInOut
	);

	/**
	 * exchange uses Vesta's traders but with your own routing.
	 * @param _receiver the wallet that will receives the output token
	 * @param _firstTokenIn the token that will be swapped
	 * @param _firstAmountIn the amount of Token In you will send
	 * @param _requests Your custom routing
	 * @return swapDatas_ elements are the amountOut from each swaps
	 *
	 * @dev this function only uses expectedAmountIn
	 */
	function exchange(
		address _receiver,
		address _firstTokenIn,
		uint256 _firstAmountIn,
		ManualExchange[] calldata _requests
	) external returns (uint256[] memory swapDatas_);

	function getAmountIn(uint256 _amountOut, ManualExchange[] calldata _requests)
		external
		returns (uint256 amountIn_);

	function getAmountOut(uint256 _amountIn, ManualExchange[] calldata _requests)
		external
		returns (uint256 amountOut_);

	/**
	 * isRegisteredTrader check if a contract is a Trader
	 * @param _trader address of the trader
	 * @return registered_ is true if the trader is registered
	 */
	function isRegisteredTrader(address _trader) external view returns (bool);

	/**
	 * getTraderAddressWithSelector get Trader address with selector
	 * @param _selector Trader's selector
	 * @return address_ Trader's address
	 */
	function getTraderAddressWithSelector(bytes16 _selector)
		external
		view
		returns (address);
}


