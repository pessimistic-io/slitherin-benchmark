// SPDX-License-Identifier: UNLICENSED
// Author: @stevieraykatz
// https://github.com/coinlander/Coinlander

pragma solidity ^0.8.8;

import "./IERC721Enumerable.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard extended for compatibiltiy with Seekers
 * @dev External Seekers.sol methods made available to inheriting contracts
 */

interface ISeekers is IERC721Enumerable {
    event FirstMintActivated();
    event SecondMintActivated();
    event ThirdMintActivated();
    event CloakingAvailable();
    event SeekerCloaked(uint256 indexed seekerId);
    event DethscalesRerolled(uint256 id);
    event PowerAdded(uint256 indexed seekerId, uint256 powerAdded, uint256 newPower);
    event PowerBurned(uint256 indexed seekerId, uint256 powerBurned, uint256 newPower);
    event SeekerDeclaredToClan(uint256 indexed seekerId, address indexed clan);


    function summonSeeker(uint256 summonCount) external payable;
    function birthSeeker(address to, uint32 holdTime) external returns (uint256);
    function keepersSummonSeeker(uint256 summonCount) external;
    function activateFirstMint() external;
    function activateSecondMint() external;
    function activateThirdMint() external;
    function seizureMintIncrement() external;
    function endGoodsOnly() external;
    function performCloakingCeremony() external;
    function sendWinnerSeeker(address winner) external;
    function cloakSeeker(uint256 id) external;
    function rerollDethscales(uint256 id) external;
    function addPower(uint256 id, uint256 powerToAdd) external;
    function burnPower(uint256 id, uint16 powerToBurn) external;
    function declareForClan(uint id, address clanAddress) external;
    function ownerWithdraw() external payable;

    /**
    * @dev Externally callable methods for Seeker attributes
    */
    function getOriginById(uint256 id) external view returns (bool);
    function getAlignmentById(uint256 id) external view returns (string memory);
    function getApById(uint256 id) external view returns (uint8[4] memory);
    function getPowerById(uint256 id) external view returns (uint16);
    function getClanById(uint256 id) external view returns (address);
    function getDethscalesById(uint256 id) external view returns (uint16);
    function getCloakStatusById(uint256 id) external view returns (bool);
    function getFullCloak(uint256 id) external view returns (uint32[32] memory);
}
