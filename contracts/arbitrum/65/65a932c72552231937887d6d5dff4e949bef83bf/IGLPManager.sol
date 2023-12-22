// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

interface IGLPManager {
	function getAumInUsdg(bool maximise) external view returns (uint256);
}

