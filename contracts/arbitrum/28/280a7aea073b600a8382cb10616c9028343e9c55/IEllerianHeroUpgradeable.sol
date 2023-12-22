pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

// Interface for upgradeable logic.
contract IEllerianHeroUpgradeable {

    function GetHeroDetails(uint256 _tokenId) external view returns (uint256[9] memory) {}
    function GetHeroClass(uint256 _tokenId) external view returns (uint256) {}
    function GetHeroLevel(uint256 _tokenId) external view returns (uint256) {}
    function GetHeroName(uint256 _tokenId) external view returns (string memory) {}
    function GetHeroExperience(uint256 _tokenId) external view returns (uint256[2] memory) {}
    function GetAttributeRarity(uint256 _tokenId) external view returns (uint256) {}

    function GetUpgradeCost(uint256 _level) external view returns (uint256[2] memory) {}
    function GetUpgradeCostFromTokenId(uint256 _tokenId) public view returns (uint256[2] memory) {}

    function ResetHeroExperience(uint256 _tokenId, uint256 _exp) external {}
    function UpdateHeroExperience(uint256 _tokenId, uint256 _exp) external {}

    function SetHeroLevel (uint256 _tokenId, uint256 _level) external {}
    function SetNameChangeFee(uint256 _feeInWEI) external {}
    function SetHeroName(uint256 _tokenId, string memory _name) public {}

    function SynchronizeHero (bytes memory _signature, uint256[] memory _data) external {}
    function IsStaked(uint256 _tokenId) external view returns (bool) {}
    function Stake(uint256 _tokenId) external {}
    function Unstake(uint256 _tokenId) external {}

    function initHero(uint256 _tokenId, uint256 _str, uint256 _agi, uint256 _vit, uint256 _end, uint256 _intel, uint256 _will, uint256 _total, uint256 _class) external {}

    function AttemptHeroUpgrade(address sender, uint256 tokenId, uint256 goldAmountInEther, uint256 tokenAmountInEther) public {}
}
