// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IGrvPresale {
    struct MarketInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 totalTokens;
        uint256 commitmentCap;
    }

    struct MarketStatus {
        uint256 commitmentsTotal;
        uint256 minimumCommitmentAmount;
        bool finalized;
    }

    event AuctionTokenDeposited(uint256 amount);
    event AuctionTimeUpdated(uint256 startTime, uint256 endTime);
    event EndTimeUpdated(uint256 endTime);
    event AuctionPriceUpdated(uint256 minimumCommitmentAmount);
    event AuctionTreasuryUpdated(address treasury);
    event LockerUpdated(address locker);

    event AddedCommitment(address addr, uint256 commitment);
    event AuctionFinalized();
    event AuctionCancelled();

    function commitETH(address payable _beneficiary) external payable;
    function commitTokens(uint256 _amount) external;

    function afterMonth(uint256 timestamp) external pure returns (uint256);
    function tokenPrice() external view returns (uint256);

    function withdrawTokens(address payable beneficiary) external;
    function withdrawToLocker() external;
    function setNickname(address _addr, string calldata _name) external;

    function tokensClaimable(address _user) external view returns (uint256);
    function tokensLockable(address _user) external view returns (uint256);

    function finalized() external view returns (bool);
    function auctionSuccessful() external view returns (bool);
    function auctionEnded() external view returns (bool);

    function getBaseInformation() external view returns (uint256 startTime, uint256 endTime, bool marketFinalized);
    function getTotalTokens() external view returns (uint256);

    function commitments(address user) external view returns (uint256);
    function claimed(address user) external view returns (uint256);
    function locked(address user) external view returns (uint256);

    function nicknames(address user) external view returns (string memory);

    function auctionToken() external view returns (address);
    function paymentCurrency() external view returns (address);

    function marketStatus() external view returns (uint256, uint256, bool);
    function marketInfo() external view returns (uint256, uint256, uint256, uint256);
}

