// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IPresaleDashboard {

    struct PresaleData {
        uint256 commitmentsTotal;
        uint256 commitmentAmount;
        uint256 estimatedReceiveAmount;
        uint256 exchangeRate;
        uint256 tokenPrice;
        uint256 launchPrice;
        uint256 startDate;
        uint256 endDate;
        uint256 totalTokens;
        uint256 minimumCommitmentAmount;
        bool finalized;
    }

    struct VestingData {
        uint256 totalPurchaseAmount;
        uint256 claimedAmount;
        uint256 claimableAmount;
    }

    function getPresaleInfo(address _user) external view returns (PresaleData memory);
    function getVestingInfo(address _user) external view returns (VestingData memory);

    function receiveGrvAmount(uint256 _amount) external view returns (uint256);
}

