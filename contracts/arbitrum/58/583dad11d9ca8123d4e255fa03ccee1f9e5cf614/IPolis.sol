//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IERC721A} from "./IERC721A.sol";

interface IPolis is IERC721A {
    error OnlyMinterRoleAccess();
    error OnlyUpgradeRoleAccess();
    error CannotMintFreePolis();
    error LevelDowngrade();
    error OnlyMetadataManagerAccess();

    event Upgrade(uint256 indexed tokenId, uint8 to);
    event BaseTokenURIChanged(string from, string to);
    event ContractURIChanged(string from, string to);

    function upgrade(uint256 tokenId, uint8 level) external;

    function senateLevel(uint256 tokenId) external view returns (uint8);

    function mint() external;

    function mintAsMinter(address to) external;

    function setBaseTokenURI(string calldata baseTokenURI) external;

    function setContractURI(string calldata baseTokenURI) external;

    function boost(
        uint256 tokenId,
        uint256 from
    ) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address);

    function contractURI() external view returns (string memory);
}

