// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IIssueMarketStorage {
	struct UnderwriterInfo {
		string name;
		uint16 feeRate;
		bool isValid;
	}

	struct SFTInfo {
        address sft;
        address issuer;
        uint8 decimals;
        uint16 defaultFeeRate;
        bool isValid;
    }

    struct PurchaseLimitInfo {
        uint256 min;
        uint256 max;
        uint64 startTime;
        uint64 endTime;
        bool useWhitelist;
    }

	struct IssueInfo {
        address issuer;
        address sft;
        uint256 slot;
        address currency;
        uint256 issueQuota;
        uint256 value;
        address receiver;
        PurchaseLimitInfo purchaseLimitInfo;
        uint8 priceType;
        IssueStatus status; 
    }

    struct UnderwriterIssueInfo {
        string name;
        uint256 quota;
        uint256 value;
    }

	enum IssueStatus {
		NONE,
		ISSUING,
		CANCELLED,
		SOLD_OUT
	}
}
