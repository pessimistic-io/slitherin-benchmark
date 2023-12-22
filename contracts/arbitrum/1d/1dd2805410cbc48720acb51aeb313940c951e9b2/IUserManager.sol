// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IUserManager {
    enum AprType {
        BORED,
        MUTANT,
        SOUL
    }
    
    event Created(
        address indexed userAdrr,
        uint256 indexed tokenId,
        AprType category,
        uint256 amount,
        uint256 createdAt
    );

    struct UserGame {
        uint256 id;
        uint256 rewardT0;
        uint256 rewardT1;
        uint256 totalReward;
        uint256 tokenBalance;
        uint256[3] gameIds;
        uint256 date;
        uint256 lastClaimTime;
    }

    struct User {
        uint256 balance;
        uint256 initialBalance;
        AprType category;
        string name;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct UserDescription {
        uint256 userId;
        uint256 balance;
        uint256 apr;
        uint256 initialBalance;
        string name;
        AprType category;
    }
    
    function getUserDescription(
        uint256 tokenId
    ) external view returns (UserDescription memory userDescription);
}

