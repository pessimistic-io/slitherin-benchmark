// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGameController
{
    function HeroNFTJoinGameOfUser(address user) external view returns(uint256);
    
    function RobotNFTJoinGameOfUser(address user) external pure returns (
        uint256 BlockJoin, // the block at which the NFT robot was added to the game
        uint256 RobotId // the ID of the NFT robot
    );


}
