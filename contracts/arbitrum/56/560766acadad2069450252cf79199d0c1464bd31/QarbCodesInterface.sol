// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface QarbCodesInterface {
    function setWhiteList(
        address[] calldata addresses,
        uint8 numAllowedToMint
    ) external;

    function mintWhiteList(string memory qrCodeText) external;

    function mintFree(string memory qrCodeText) external;

    function mint(string memory qrCodeText, uint256 count) external payable;

    function mintTeam(string memory qrCodeText, uint256 count) external;

    function toggleLaunch() external;

    function togglePublicSaleActive() external;

    function withdrawBalance(address payable to) external;

    function maxSupply() external view returns (uint256);

    function tokenQrCodeText(
        uint256 tokenId
    ) external view returns (string memory);

    function whiteListSpots(address addr) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function currentMintPrice() external view returns (uint256);
}

