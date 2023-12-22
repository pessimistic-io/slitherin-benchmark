// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @author DeFragDAO
interface IQualifier {
    function getUsersAllowList() external view returns (address[] memory);

    function getTokenIdsAllowList() external view returns (uint256[] memory);

    function isUserAllowListed(
        address _userAddress
    ) external view returns (bool);

    function isTokenIdAllowListed(
        uint256 _tokenId
    ) external view returns (bool);

    function addToUsersAllowList(address _userAddress) external;

    function addToTokenIdsAllowList(uint256 _tokenId) external;

    function removeFromUsersAllowList(address _userAddress) external;

    function removeFromTokenIdsAllowList(uint256 _tokenId) external;
}

