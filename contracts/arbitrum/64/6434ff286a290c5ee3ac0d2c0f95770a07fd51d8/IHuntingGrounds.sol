// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IHuntingGrounds {

    function startHunting(uint256 _tokenId) external;

    function stopHunting(uint256 _tokenId, address _owner) external;
}
