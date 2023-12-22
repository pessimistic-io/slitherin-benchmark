// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./IERC721.sol";

interface IMSW721 is IERC721 {
    function cardInfoes(
        uint256
    ) external view returns (uint256, uint256, uint256, uint256, string memory);

    function cardIdMap(uint256) external view returns (uint256);

    function cardOwners(uint256) external view returns (address);

    function minters(address, uint256) external view returns (uint256);

    function superMinters(address) external view returns (bool);

    function myBaseURI() external view returns (string memory);

    function superMinter() external view returns (address);

    function WALLET() external view returns (address);

    function mint(address, uint, uint) external returns (bool);

    function upgrade(uint, uint) external returns (bool);
}

