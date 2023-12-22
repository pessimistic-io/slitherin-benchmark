//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./CityClashNFT.sol";

contract CityClashScore is CityClashNFT {
    
    event CountryChangedEvent(string country);

    uint256 public redScore = 0;
    uint256 public greenScore = 0;
    uint256 public blueScore = 0;
    
    function hasUploadedMetadata(CityClashTypes.City memory city) internal pure returns (bool) {
        return city.points != 0;
    }

    function getCountryFaction(string memory country) public view returns (uint8) {
        CityClashTypes.CountryScore memory countryScore = countryToScore[country];
        return getWinningFaction(countryScore.red, countryScore.green, countryScore.blue);
    }

    function getWinningFaction(uint _redPoints, uint _greenPoints, uint _bluePoints) public pure returns (uint8) {
        if(_redPoints > _greenPoints && _redPoints > _bluePoints) {
            return 1;
        } else if(_greenPoints > _redPoints && _greenPoints > _bluePoints) {
            return 2;
        } else if(_bluePoints > _redPoints && _bluePoints > _greenPoints) {
            return 3;
        }
        return 4; //incase of tie
    }

    function getLosingFaction(uint _redPoints, uint _greenPoints, uint _bluePoints) public pure returns (uint8) {
        if(_redPoints < _greenPoints && _redPoints < _bluePoints) {
            return 1;
        } else if(_greenPoints < _redPoints && _greenPoints < _bluePoints) {
            return 2;
        }
        return 3;
    }

    function getOverallLosingFaction() public view returns (uint8) {
        return getLosingFaction(redScore, greenScore, blueScore);
    }

    function updateFactionScore(uint countryPoints, uint8 previousWinningFaction, CityClashTypes.City memory city) internal {
        CityClashTypes.CountryScore storage countryScore = countryToScore[city.country];
        //recount after change
        uint8 winningFactionAfter = getWinningFaction(countryScore.red, countryScore.green, countryScore.blue);
        console.log('winning faction after', winningFactionAfter);
        if(previousWinningFaction != winningFactionAfter) {
            if(previousWinningFaction == 1) {
                redScore -= countryPoints;
            } else if(previousWinningFaction == 2) {
                greenScore -= countryPoints;
            } else if(previousWinningFaction == 3) {
                blueScore -= countryPoints;
            }
            if(winningFactionAfter == 1) {
                redScore += countryPoints;
            } else if(winningFactionAfter == 2) {
                greenScore += countryPoints;
            } else if(winningFactionAfter == 3) {
                blueScore += countryPoints;
            }
            emit CountryChangedEvent(city.country);
        }
    }
}
