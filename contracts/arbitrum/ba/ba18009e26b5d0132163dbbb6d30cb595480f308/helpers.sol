//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import { TokenInterface } from "./interfaces.sol";
import { DSMath } from "./math.sol";
import { Basic } from "./basic.sol";
import { IConnext } from "./interface.sol";

contract Helpers is DSMath, Basic {
	/**
	 * @dev Connext Diamond Address
	 */
	address internal constant connextAddr =
		0xEE9deC2712cCE65174B561151701Bf54b99C24C8;
	IConnext internal constant connext = IConnext(connextAddr);

	/**
	 * @param destination The destination domain ID.
	 * @param asset The address of token to be bridged.
	 * @param delegate Address that can revert or forceLocal on destination.
	 * @param amount The amount to transfer.
	 * @param slippage Maximum amount of slippage the user will accept in BPS.
	 * @param relayerFee Relayer fee paid in origin native asset.
	 * @param callData Encoded calldata to send.
	 */
	struct XCallParams {
		uint32 destination;
		address to;
		address asset;
		address delegate;
		uint256 amount;
		uint256 slippage;
		uint256 relayerFee;
		bytes callData;
	}

	function _xcall(XCallParams memory params) internal {
		connext.xcall{ value: params.relayerFee }(
			params.destination,
			params.to,
			params.asset,
			params.delegate,
			params.amount,
			params.slippage,
			params.callData
		);
	}
}

