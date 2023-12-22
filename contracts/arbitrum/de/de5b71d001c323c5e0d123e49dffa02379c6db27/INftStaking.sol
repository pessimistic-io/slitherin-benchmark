// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

interface INftStaking {
    function gameSetLastUpdate(address _user, uint256 lastUpdate) external;
    function getPowerUp(address _address) external view returns(uint256);
    function gameHarvest(address _user) external;
    function getMaxSlots(address _address) external view returns(uint256);

}
