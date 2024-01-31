// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

library Helper {
	function safeTransferNative(address _to, uint256 _value) internal {
		(bool success, ) = _to.call { value: _value }(new bytes(0));
		require(success, "SafeTransferNative: transfer failed");
	}
}
