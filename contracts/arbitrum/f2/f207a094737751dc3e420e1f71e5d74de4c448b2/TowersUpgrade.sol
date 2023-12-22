//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./console.sol";
import "./Ownable.sol";
import "./CityClashTowersInterface.sol";
import "./CityClashTypes.sol";
import "./CityClashInterface.sol";
import { Base64 } from "./Base64.sol";

contract TowersUpgrade is Ownable {

    event UpgradeCityEvent(uint);

    address public cityClashTowersAddress = 0x45d86E0dB60c4AEE3dFea312d8F4b5eE87E4886a;
    address public cityClashAddress = 0x31949446395e16A294108a25bfcC4937799FA8Ef;
    bool public isPaused = false;
    bool public isImageUpgradePaused = false;
    mapping(uint => bool) public isCityUpgraded;

    constructor() { }

    modifier whenNotPaused() {
        require(!isPaused, "The contract is paused.");
        _;
    }

    modifier whenNotImageUpgradePaused() {
        require(!isImageUpgradePaused, "The image upgrade is paused.");
        _;
    }

    function upgradeCityAndBurnTower(uint _cityTokenId, uint _towerTokenId) public whenNotPaused {
        CityClashInterface cityClash = CityClashInterface(cityClashAddress);
        require(cityClash.ownerOf(_cityTokenId) == msg.sender, "You must be the owner of the city to upgrade it");

        CityClashTowersInterface cityClashTowers = CityClashTowersInterface(cityClashTowersAddress);
        require(cityClashTowers.ownerOf(_towerTokenId) == msg.sender, "You must be the owner of the tower to upgrade your city");
        require(cityClashTowers.idToNumStories(_towerTokenId) > 3, "Tower must be at least 4 stories high to upgrade city");

        require(isCityUpgraded[_cityTokenId] != true, "City must have not already been upgraded");
        
        uint amountToUpgrade = cityClashTowers.idToNumStories(_towerTokenId) / 4;

        //Do the upgrades
        cityClash.upgradeCity(_cityTokenId, amountToUpgrade, true);
        cityClashTowers.burnByCityClashContract(_towerTokenId, msg.sender);
        isCityUpgraded[_cityTokenId] = true;

        emit UpgradeCityEvent(_cityTokenId);
    }
    
    function upgradeCityImageAndBurnTower(uint _cityTokenId, uint _towerTokenId, string memory _imageBaseUrl) external whenNotPaused whenNotImageUpgradePaused {
        CityClashInterface cityClash = CityClashInterface(cityClashAddress);
        upgradeCityAndBurnTower(_cityTokenId, _towerTokenId);
        cityClash.updateCityImage(_cityTokenId, _imageBaseUrl);
    }

    function setCityClashAddress(address _newAddress) external onlyOwner {
        cityClashAddress = _newAddress;
    }

    function setCityClashTowersAddress(address _newAddress) external onlyOwner {
        cityClashTowersAddress = _newAddress;
    }

    function setIsPaused(bool _newIsPaused) external onlyOwner {
        isPaused = _newIsPaused;
    }

    function setIsImageUpgradePaused(bool _newIsPaused) external onlyOwner{
        isImageUpgradePaused = _newIsPaused;
    }
}
