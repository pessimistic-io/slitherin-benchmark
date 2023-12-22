// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

interface IGridFireEditions {
    struct GridFireEdition {
        uint256 price;
        string uri;
    }

    event EditionMinted(
        bytes32 indexed releaseId,
        address indexed artist,
        bytes32 indexed objectId,
        uint256 editionId,
        uint256 amount,
        uint256 price
    );

    event PurchaseEdition(
        address indexed buyer,
        address indexed artist,
        uint256 indexed editionId,
        uint256 amountPaid,
        uint256 artistShare,
        uint256 platformFee,
        bytes32 releaseId
    );

    event Received(address from, uint256 amount);

    receive() external payable;

    function mintEdition(
        uint256 amount,
        uint256 price,
        string calldata metadataUri,
        bytes32 releaseId,
        bytes32 objectId
    ) external;

    function purchaseGridFireEdition(
        uint256 editionId,
        uint256 amountPaid,
        address paymentAddress,
        bytes32 releaseId
    ) external;

    function withdraw() external;
}

