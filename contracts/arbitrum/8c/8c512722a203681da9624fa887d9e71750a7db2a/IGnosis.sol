// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.20;

interface IGnosis {
	function isValidSignature(bytes calldata _data, bytes calldata _signature) external view returns (bytes4);
}

