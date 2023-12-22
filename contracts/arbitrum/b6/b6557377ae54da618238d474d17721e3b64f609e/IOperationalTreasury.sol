// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.20;

interface IOperationalTreasury {
    enum State {
        Listed,
        Active,
        Closed,
        Released
    }

    enum Protocol {
        Active,
        Paused
    }

    struct terData {
        uint256 tokenID;
        address holder;
        uint256 hegicBalance;
        uint256 listForEpoch;
        uint256 expiryAt;
        uint256 price;
        State state;
    }

    event Listed(
        uint256 indexed terTokenID,
        uint256 price,
        uint256 hegicBalance
    );

    event Purchased(uint256 indexed tokenId, address buyer, uint256 price);
    event Claimed(
        uint256 indexed terTokenID,
        uint256 rewardAmount,
        address indexed buyer
    );
    event Released(uint256 indexed hegicTokenID, address indexed holder);
    event EpochClosed(uint256 indexed epochNum);
    event ClaimTimeExtended(uint256 newClaimTime);
    event RewardsClaimedOnBehalf(uint256 indexed terId, address indexed buyer, uint256 amount);

    function depositAndList(uint256 hegicTokenId, uint256 price) external;

    function buyTER(uint256 terId) external;

    function claim(uint256 terId) external;

    function closeEpoch(uint256 epochNum) external;

    function changePrice(uint256 TERid, uint256 newPrice) external;

    function delistAndRetrieve(uint256 terId) external;

    function checkEpochPnL(uint256 epochID) external view returns (bool);

    function computeCurrentEpochEndTime() external view returns (uint256);

    function computeClaimTime(uint256 epochNum) external view returns (uint256);

    function getCurrentEpoch() external view returns (uint256);

}

