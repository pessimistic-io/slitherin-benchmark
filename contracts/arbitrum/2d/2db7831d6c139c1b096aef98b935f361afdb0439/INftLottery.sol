// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface INftLottery {

    enum PrizeType {
        ETH,
        ERC20,
        ERC721
    }

    struct Prize {
        address asset;
        uint amount;
        uint tokenId;
        PrizeType prizeType;
    }

    struct LotteryList {
        uint luckyTokenId;
        address winner;
        Prize prize;
    }

    function prizeCount() external view returns(uint);
    function phaseIsLottery(uint phase) external view returns(bool);
    function getUserLotteryResults(uint _phase, address _user) external view returns(bool[] memory);
    function phaseLotteryLists(uint phase, uint index) external view returns(LotteryList memory);
    function phaseIsExpire(uint phase) external view returns(bool);
}

