// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface CityClashTowersInterface {
    function idToNumStories(uint _tokenId) external returns (uint);
    function ownerOf(uint _tokenId) external view returns (address);
    function burnByCityClashContract(uint _tokenId, address _ownerAddress) external;
}
