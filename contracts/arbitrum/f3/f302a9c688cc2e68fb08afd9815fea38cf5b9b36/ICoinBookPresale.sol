// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface ICoinBookPresale {

	struct UserInfo {
        uint256 wlContributed;
        uint256 psContributed;
        uint256 wlClaimed;
        uint256 wlRefunded;
        uint256 psClaimed;
        uint256 psRefunded;
        bool claimed;
    }

    struct PresaleInfo {
    	uint80 startTime;
    	uint80 endTime;
    	uint256 maxSpend;
    	uint256 target;
    	uint256 saleAmount;
    	uint256 raisedAmount;
    }

    event Contributed(address indexed user, uint256 amount, string stage, uint256 timeStamp);

    event SwappedToUSDC(address indexed user, uint256 swappedETH, uint256 receivedUSDC);

    event Claimed(
    	address indexed user, 
    	uint256 totalClaimed, 
    	uint256 totalRefunded, 
    	uint256 claimedFromWhitelist, 
    	uint256 claimedFromPublicSale, 
    	uint256 refundedFromWhitelist, 
    	uint256 refundedFromPublicSale, 
    	uint256 timeStamp
    );

    event UpdatedManyWhitelist(address[] users, bool isWhitelisted);

    event UpdatedSingleWhitelist(address user, bool isWhitelisted);

    event PresaleFinalized(
    	uint256 totalRaised, 
    	uint256 whitelistRaised, 
    	uint256 publicRaised,
    	uint256 adjustedCoreRaised,
    	uint256 excessBookNotSold,
    	uint256 timeStamp
    );

    event TimesExtended(
    	uint80 whitelistSaleStart, 
    	uint80 whitelistSaleEnd, 
    	uint80 publicSaleStart, 
    	uint80 publicSaleEnd, 
    	uint80 claimPeriodStart
    );

    event Received(address sender, uint256 amount);

    receive() external payable;

    function contributeInWhitelist(uint256 _amount) external;

    function swapAndContributeInWhitelist(uint256 minAmount) external payable;

    function contributeInPublic(uint256 _amount) external;

    function swapAndContributeInPublic(uint256 minAmount) external payable;

    function claimBook() external;

    function claimExcessWhitelist(bool moveToPublic) external;

    function fundContract() external;

    function finalizePresale() external;

    function extendTimes(
    	uint80 _wlStart, 
    	uint80 _wlEnd, 
    	uint80 _psStart, 
    	uint80 _psEnd, 
    	uint80 _claimStart
    ) external;

    function updateManyWhitelist(address[] calldata _users, bool _flag) external;

    function updateSingleWhitelist(address _user, bool _flag) external;

    function getAmountsRaised() external view returns (
    	uint256 totalRaised, 
    	uint256 whitelistRaised, 
    	uint256 publicRaised
    );

    function getPresaleStatus() external view returns (uint8 status);

    function getClaimableAmounts(
        address _user
    ) external view returns (
        uint256 wlBook, 
        uint256 wlRefund, 
        uint256 psBook, 
        uint256 psRefund
    );

    function getWhitelistSaleInfo() external view returns (
        uint80 startTime,
        uint80 endTime,
        uint256 maxSpend,
        uint256 target,
        uint256 saleAmount,
        uint256 raisedAmount
    );

    function getPublicSaleInfo() external view returns (
        uint80 startTime,
        uint80 endTime,
        uint256 maxSpend,
        uint256 target,
        uint256 saleAmount,
        uint256 raisedAmount
    );
}
