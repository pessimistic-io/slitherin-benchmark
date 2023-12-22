// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IAffiliate {
    struct Tiers {
        uint volume;   //in whole unit, so it is 1 for 1USDC not 1e6 !!!!
        uint selfVolume; //self(i.e. cashback)
        uint refShare; //used to calculate rewards based on referrals stats, % 
        uint selfShare; //used to calculate rewards based on self stats, %
    }

    struct UserStats {
        uint investmentDigital; //investment amount for digitla options
        uint refInvestmentDigital;//referrals investment amount
        uint volumeClassic;//classic options
        uint refVolumeClassic;
        uint payoff; // gain/loss of binary
        uint fees;//paid fees 
        uint refPayoff; // gain/loss of binary
        uint refFees; 
    }

    struct User {
      uint timeSync;//track if month has passed
      uint128 refInvestmentDigital; // LTD total referred inflow
      uint128 refRewards; // LTD total rewards claimed
      address referer;
    }

    /*function getShares(uint selfVolume, uint refVolume, bool optionType)
        external
        view 
        returns(uint refShare, uint selfShare);
    */
    function addUser(address user) external;
    function addReferal(address user, address referer) external;
    function getUserStats(address user, address token) 
        external
        view
        returns(UserStats memory userStats);
    function showUserRewards(address user, address token)
        external
        view
        returns(uint);
    function checkUserExists(address user) external view returns(bool);
    function getParent(address user) external view returns(address);

    function updateVolume(address user, uint volume, address token, bool isDigital) external;
    function updateStats(address user, uint volume, uint amount, address token, bool isDigital) external;
    
    function claimReward(address token) external;
    
    function addTier(uint volume, uint selfVolume, uint refShare, uint selfShare, bool isDigital) external;
    function updateTier(uint volume, uint selfVolume, uint refShare, uint selfShare, uint index, bool isDigital) external;
}

