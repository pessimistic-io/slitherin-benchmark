// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./TransferHelper.sol";

import "./TokenRewardCampaign.sol";

contract TokenRewardCampaignManager is Ownable {
    // State variables
    TokenRewardCampaign[] public campaigns;
    mapping(address => TokenRewardCampaign[]) public campaignsByCreator;
    mapping(address => bool) public isCampaign;

    // Events
    event CampaignCreated(address campaign);
    event CampaignApproved(address campaign);
    event CampaignDisapproved(address campaign);

    modifier onlyCampaignOwner(address campaignAddress) {
        TokenRewardCampaign targetCampaign = TokenRewardCampaign(campaignAddress);

        require(msg.sender == targetCampaign.owner(), "Only owner can approve campaigns");
        _;
    }

    function getCampaignsByCreator(address creator) external view returns (TokenRewardCampaign[] memory creatorCampagins) {
        creatorCampagins = campaignsByCreator[creator];
    }

    // Function to create a new campaign
    function createCampaign(address _rewardToken, uint256 _rewardAmount, uint256 _rewardSeats, TokenRewardCampaign.CampaignType _campaignType) public {
        TokenRewardCampaign newCampaign = new TokenRewardCampaign(msg.sender, _rewardToken, _rewardAmount, _rewardSeats, _campaignType, address(this), owner());
        campaigns.push(newCampaign);
        campaignsByCreator[msg.sender].push(newCampaign);
        isCampaign[address(newCampaign)] = true;

        TransferHelper.safeApprove(
            _rewardToken,
            address(newCampaign),
            _rewardAmount
        );

        TransferHelper.safeTransferFrom(
            _rewardToken,
            msg.sender,
            address(newCampaign),
            _rewardAmount
        );

        emit CampaignCreated(address(newCampaign));
    }

    function forceFinishCampaign(address campaignAddress) public onlyCampaignOwner(campaignAddress) {
        TokenRewardCampaign newCampaign = TokenRewardCampaign(campaignAddress);
        newCampaign.finishRaffleCampaign();
    }
 
    // Function to approve a campaign
    function approveCampaign(address campaignAddress) public onlyCampaignOwner(campaignAddress) {
        require(isCampaign[campaignAddress], "Campaign does not exist");

        TokenRewardCampaign(campaignAddress).startCampaign();

        emit CampaignApproved(campaignAddress);
    }

    // Function to disapprove a campaign
    function disapproveCampaign(address campaignAddress) public onlyCampaignOwner(campaignAddress) {
        require(isCampaign[campaignAddress], "Campaign does not exist");

        TokenRewardCampaign(campaignAddress).withdrawFunds();

        emit CampaignDisapproved(campaignAddress);
    }
}

