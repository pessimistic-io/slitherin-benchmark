// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { ManualExchange, RouteConfig } from "./TradingModel.sol";

interface IVestaDexTrader {
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

	// /**
	//  * isRegisteredTrader check if a contract is a Trader
	//  * @param _trader address of the trader
	//  * @return registered_ is true if the trader is registered
	//  */
	// function isRegisteredTrader(address _trader)
	// 	external
	// 	view
	// 	returns (bool);

	// /**
	//  * getTraderAddressWithSelector get Trader address with selector
	//  * @param _selector Trader's selector
	//  * @return address_ Trader's address
	//  */
	// function getTraderAddressWithSelector(bytes16 _selector)
	// 	external
	// 	view
	// 	returns (address);

	// /**
	//  * getRouteOf get the routes config between two tokens
	//  * @param _tokenIn token you want to swap
	//  * @param _tokenOut the token outcome of the swap
	//  * @return routes the configured routes
	//  */
	// function getRouteOf(address _tokenIn, address _tokenOut)
	// 	external
	// 	view
	// 	returns (RouteConfig[] memory);
}


