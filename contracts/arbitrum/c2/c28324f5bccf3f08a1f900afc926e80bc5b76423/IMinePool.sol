
// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface IMinePool {
    struct MineBrief {
        uint8 nftType;
        uint8 gen;
        uint32 tokenId;
        uint32[] wells;
        uint256 power;
        uint256 capacity; //油田储能
        uint256 output; //架设油井后的产量
        uint256 pendingRewards; //待领取Oil的数量
        uint256 equivalentOutput; //待领取Oil以USDT计算的产量
        uint256 cumulativeOutput; //累计产量
        uint256 lastClaimTime;
    }

    struct PoolOilInfo {
        uint8 cid;
        uint256 basePct;
        uint256 dynamicPct;
        uint256 oilPerSec;
        uint256 totalCapacity;
    }

    function mineBrief(uint32 _mineId) external view returns(MineBrief memory);
    function totalMineInfo() external view returns(
        uint8   k_,
        bool    addition_,
        uint32  claimCD_,
        uint32  basePct_,
        uint256 oilPerSec_,
        PoolOilInfo[3] memory info_
    );
    function addCapacity(uint32 _mineId, uint256 _capacity) external;
    function pendingRewards(uint32 _mineId) external view returns(uint256);
    function updatePool() external;
    function isWorkingMine(uint32 _mineId) external view returns(bool);
    function voteDynamicPct(uint256[3] memory _dynamicPct) external;
}
