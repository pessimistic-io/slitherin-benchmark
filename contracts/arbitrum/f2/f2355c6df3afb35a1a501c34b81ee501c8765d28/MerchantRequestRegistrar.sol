// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC721.sol";

contract MerchantRequestRegistrar is ERC721 {
    struct MerchantIDRequest {
        string ensRequestedName;
        string companyName;
        string companyAddress;
        int256 latitude;
        int256 longitude;
        string color;
        string logo;
        string category;
    }

    mapping(uint256 => MerchantIDRequest) public merchantIDRequests;
    mapping(string => bool) private ensNames;
    uint256 private tokenIds;

    event ENSRegistrationData(
        uint256 indexed tokenId,
        string ensRequestedName,
        address indexed owner
    );

    constructor() ERC721("MerchantRequestRegistrar", "MREQ") {}

    modifier onlyTokenOwner(uint256 tokenId) {
        require(
            ownerOf(tokenId) == msg.sender,
            "Caller is not the owner of this token"
        );
        _;
    }

    function registerMerchant(
        string memory ensRequestedName,
        string memory companyName,
        string memory companyAddress,
        int256 latitude,
        int256 longitude,
        string memory color,
        string memory logo,
        string memory category
    ) external {
        require(bytes(ensRequestedName).length > 0, "ENS name is required");
        require(bytes(companyName).length > 0, "Company name is required");
        require(
            bytes(companyAddress).length > 0,
            "Company address is required"
        );
        require(
            latitude >= -90 * 1e6 && latitude <= 90 * 1e6,
            "Latitude must be between -90 and 90 degrees (scaled by 1e6)"
        );
        require(
            longitude >= -180 * 1e6 && longitude <= 180 * 1e6,
            "Longitude must be between -180 and 180 degrees (scaled by 1e6)"
        );
        require(bytes(color).length > 0, "Color is required");
        require(bytes(logo).length > 0, "Logo URL is required");
        require(bytes(category).length > 0, "Category is required");

        require(!ensNames[ensRequestedName], "ENS name already exists");
        ensNames[ensRequestedName] = true;

        tokenIds++;

        // Mint the NFT
        _mint(msg.sender, tokenIds);

        // Store the merchant request data
        merchantIDRequests[tokenIds] = MerchantIDRequest(
            ensRequestedName,
            companyName,
            companyAddress,
            latitude,
            longitude,
            color,
            logo,
            category
        );

        // Emit the ENSRegistrationData event
        emit ENSRegistrationData(tokenIds, ensRequestedName, msg.sender);
    }

    function updateMerchant(
        uint256 tokenId,
        string memory ensRequestedName,
        string memory companyName,
        string memory companyAddress,
        int256 latitude,
        int256 longitude,
        string memory color,
        string memory logo,
        string memory category
    ) external onlyTokenOwner(tokenId) {
        // Update the merchant request data
        merchantIDRequests[tokenId] = MerchantIDRequest(
            ensRequestedName,
            companyName,
            companyAddress,
            latitude,
            longitude,
            color,
            logo,
            category
        );
    }
}

