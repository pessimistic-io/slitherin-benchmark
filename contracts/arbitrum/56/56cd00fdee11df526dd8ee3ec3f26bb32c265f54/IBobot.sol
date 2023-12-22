// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IBobot 
{
    enum BobotType
    {
        BOBOT_GEN,
        BOBOT_NANO,
        BOBOT_MEGA
    }

    struct UserInfo
    {
        uint256 numberofBobots;
        uint256 magicinWallet;
        BobotType bobotType;
    }

    // ------------------ VIEW FUNCTIONS -----------------
    function getBobotType() external view returns (BobotType);
    function getTokenURI(uint256 _tokenID) external view returns (string memory);
}

