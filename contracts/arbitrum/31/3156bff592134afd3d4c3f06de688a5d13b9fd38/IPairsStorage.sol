// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPairsStorage {

    enum FeedCalculation {
        DEFAULT,
        INVERT,
        COMBINE
    } // FEED 1, 1 / (FEED 1), (FEED 1)/(FEED 2)
    
    struct Feed {
        address feed1;
        address feed2;
        FeedCalculation feedCalculation;
        uint256 maxDeviationP;
    } 

    function incrementCurrentOrderId() external returns (uint256);

    function updateGroupCollateral(uint256, uint256, bool, bool) external;

    function pairJob(uint256) external returns (string memory, string memory, bytes32, uint256);

    function pairFeed(uint256) external view returns (Feed memory);

    function pairSpreadP(uint256) external view returns (uint256);

    function pairMinLeverage(uint256) external view returns (uint256);

    function pairMaxLeverage(uint256) external view returns (uint256);

    function groupMaxCollateral(uint256) external view returns (uint256);

    function groupCollateral(uint256, bool) external view returns (uint256);

    function guaranteedSlEnabled(uint256) external view returns (bool);

    function pairOpenFeeP(uint256) external view returns (uint256);

    function pairCloseFeeP(uint256) external view returns (uint256);

    function pairOracleFeeP(uint256) external view returns (uint256);

    function pairExecuteLimitOrderFeeP(uint256) external view returns (uint256);

    function pairReferralFeeP(uint256) external view returns (uint256);

    function pairMinLevPosStable(uint256) external view returns (uint256);

    function pairsCount() external view returns (uint256);
}

