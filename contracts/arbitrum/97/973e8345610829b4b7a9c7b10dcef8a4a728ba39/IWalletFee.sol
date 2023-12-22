// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./IFunWallet.sol";

interface IWalletFee {
	function execFromEntryPoint(address dest, uint256 value, bytes calldata data) external;

	function execFromEntryPointWithFee(address dest, uint256 value, bytes calldata data, UserOperationFee memory feedata) external;
}

