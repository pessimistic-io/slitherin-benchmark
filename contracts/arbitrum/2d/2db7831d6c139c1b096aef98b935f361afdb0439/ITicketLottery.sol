// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ITicketLottery {
    enum Item{
        FIRST_PRIZE,
        SECOND_PRIZE,
        THIRD_PRIZE,
        NFT_DIVIDEND,
        PLATFORM_RAKE,
        REPO_DESTROY
    }

    function phaseReceivedJackpot(uint phase) external view returns(uint);
    function getPhaseItemRewards(uint phase, Item item) external view returns(uint);
    function phaseLotteryLuckyNo(uint phase, uint index) external view returns(uint);
    function phaseLuckyNo(uint phase,uint index) external view returns(uint);
    function isLottery(uint phase) external view returns(bool);
}
