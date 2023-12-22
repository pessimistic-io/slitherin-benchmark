// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./TrendsSharesV1.sol";

contract TrendsSharesHelper {
    TrendsSharesV1 public trendsShares;

    constructor(address _trendsSharesAddress) {
        trendsShares = TrendsSharesV1(_trendsSharesAddress);
    }

    struct SubjectInfo {
        uint256 shares;
        uint256 earnings;
    }

    struct SubjectPrice {
        bytes32 subject;
        uint256 price;
    }

    function getSharesAndEarnings(address wallet, bytes32[] memory subjects) external view returns (SubjectInfo[] memory) {
        SubjectInfo[] memory subjectInfos = new SubjectInfo[](subjects.length);

        for (uint i = 0; i < subjects.length; i++) {
            bytes32 subject = subjects[i];

            // Get the shares balance from the TrendsSharesV1 contract
            uint256 shares = trendsShares.sharesBalance(subject, wallet);

            // Get the earnings using reward details from TrendsSharesV1 contract
            uint256 earnings = trendsShares.getReward(subject, wallet);

            subjectInfos[i] = SubjectInfo(shares, earnings);
        }

        return subjectInfos;
    }

    function getLatestPrices(bytes32[] memory subjects) external view returns (SubjectPrice[] memory) {
        SubjectPrice[] memory subjectPrices = new SubjectPrice[](subjects.length);

        for (uint i = 0; i < subjects.length; i++) {
            bytes32 subject = subjects[i];

            uint24 declineRatio = trendsShares.sharesDeclineRatio(subject);
            uint256 supply = trendsShares.sharesSupply(subject);

            // Assuming amount is 1 to get the current price
            uint256 price = trendsShares.getPrice(supply, 1, declineRatio);
            subjectPrices[i] = SubjectPrice(subject, price);
        }

        return subjectPrices;
    }

}

