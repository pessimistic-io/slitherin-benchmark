// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

library CallLib {
	/**
	 * invoke the downstream module contract to execute the action
	 * @param dest the destination address to forward the call to
	 * @param value the amount of ether to forward to @dest
	 * @param data the call data
	 * @return result the bytes result returned from the downstream call
	 */
	function exec(address dest, uint256 value, bytes memory data) internal returns (bytes memory) {
		(bool success, bytes memory result) = payable(dest).call{value: value}(data);
		if (success == false) {
			assembly {
				revert(add(result, 32), mload(result))
			}
		}
		return result;
	}
}

