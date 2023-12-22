// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./EnumerableSet.sol";
import "./OwnControl.sol";
import "./IIssueMarketStorage.sol";

contract IssueMarketStorage is IIssueMarketStorage, OwnControl {
	// keccak256(underwriterName)
	mapping(bytes32 => UnderwriterInfo) public underwriterInfos;
	
	// underwriterKey => currency => profitSlot
	mapping(bytes32 => mapping(address => uint256)) underwriterProfitSlot;

	EnumerableSet.Bytes32Set underwriterKeys;

	mapping(address => SFTInfo) public sftInfos;
	
	mapping(address => bool) public currencies;

	// keccak256(sft,slot) => IssueInfo
	mapping(bytes32 => IssueInfo) public issueInfos;

	// keccak256(sft,slot) => priceInfo
	mapping(bytes32 => bytes) public priceInfos;

	// keccak256(sft,slot) => buyer => purchased amount
	mapping(bytes32 => mapping(address => uint256)) public purchasedRecords;

	// keccak256(underwriterName) => keccak256(sft,slot) => underwriterIssueInfo
	mapping(bytes32 => mapping(bytes32 => UnderwriterIssueInfo)) public underwriterIssueInfos;

	// currency => fee amount
	mapping(address => uint256) public totalReservedFees;

    uint256[40] private __gap;
}
