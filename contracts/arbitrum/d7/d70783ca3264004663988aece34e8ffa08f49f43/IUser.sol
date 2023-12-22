// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

interface IUser {
    enum REV_TYPE { MINT_NFT_ADDR, LRT_ADDR, AP_ADDR,LYNK_ADDR,UP_CA_ADDR,MARKET_ADDR,USDT_ADDR }
    enum Level {
        elite,
        epic,
        master,
        legendary,
        mythic,
        divine
    }

    function isValidUser(address _userAddr) view external returns (bool);

    function hookByUpgrade(address _userAddr, uint256 _performance) external;
    function hookByClaimReward(address _userAddr, uint256 _rewardAmount) external;
    function hookByStake(uint256 nftId) external;
    function hookByUnStake(uint256 nftId) external;
    function registerByEarlyPlan(address _userAddr, address _refAddr) external;

}

