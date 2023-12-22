// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./CityClashTypes.sol";

interface CityClashInterface {

    function MAX_CITIES() external view returns (uint256);
    function FOUNDERS_RESERVE_AMOUNT() external view returns (uint256);
    function idToCitiesFunc(uint256 _id) external view returns (CityClashTypes.City memory);
    function ownerOf(uint256 _id) external view returns (address);
    function redScore() external view returns (uint256);
    function greenScore() external view returns (uint256);
    function blueScore() external view returns (uint256);
    function getWinningFaction(uint _redPoints, uint _greenPoints, uint _bluePoints) external pure returns (uint8);
    function getTokenIds() external view returns (uint256);
    function getReservedTokenIds() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function upgradeCity(uint _tokenId, uint points, bool isPositive) external;
    function updateCityImage(uint _tokenId, string memory _imageBaseUrl) external;
}
