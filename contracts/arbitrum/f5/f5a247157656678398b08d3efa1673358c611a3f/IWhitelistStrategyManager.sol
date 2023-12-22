// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IWhitelistStrategyManager {
	function setWhitelist(bytes32 issueKey_, address[] calldata whitelist_) external;
	function isWhitelisted(bytes32 issueKey_, address buyer_) external view returns (bool);
}
