//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IIssueMarketStorage.sol";

interface IIssueMarket is IIssueMarketStorage {
    event AddSFT(address indexed sft, address indexed issuer, uint8 decimals, uint16 defaultFeeRate);
    event RemoveSFT(address indexed sft);
    event SetCurrency(address indexed currency, bool enabled);
    event AddUnderwriter(string indexed underwriter, uint16 defaultFeeRate);
    event AddUnderwriterCurrency(string indexed underwriter, address indexed currency, uint256 indexed slot);

    event Issue(address indexed sft, uint256 indexed slot, IssueInfo info, uint8 priceType, bytes priceInfo, string[] underwriters, uint256[] quotas);
    event Subscribe(address indexed sft, uint256 indexed slot, address indexed buyer, uint256 tokenId, string underwriter, uint256 value, 
        address currency, uint256 price, uint256 payment, uint256 issueFee, uint256 underwriterFee);

    struct InputIssueInfo {
        string[] underwriters;
        uint256[] quotas;
        uint256 issueQuota;
        uint256 min;
        uint256 max;
        address receiver;
        address[] whitelist;
        uint64 startTime;
        uint64 endTime;
        uint8 priceType;
    }


	function issue(address sft_, address currency_, bytes memory inputSlotInfo_, bytes memory inputIssueInfo_, 
        bytes memory inputPriceInfo_) external payable returns (uint256 slot_);
    function subscribe(address sft_, uint256 slot_, string calldata underwriter_, uint256 value_, uint64 expireTime_) 
        external payable returns (uint256 tokenId_, uint256 payment_);
}
