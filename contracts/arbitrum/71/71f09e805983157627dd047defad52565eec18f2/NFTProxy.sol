// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";

contract NFTProxy is Ownable {
    // Blocklist marketplaces
    mapping(address => bool) private _blockedMarketplaces;

    constructor() {
        // Add blocked marketplaces
        _blockedMarketplaces[0x1ACf4D4f22EA6506ccB5f49cC05200FDC31824EB] = true; // Example marketplace address
    }

    // Modifier to restrict access to blocked marketplaces
    modifier onlyApprovedMarketplace() {
        require(!_blockedMarketplaces[msg.sender], "Access denied");
        _;
    }

    // Function to block marketplace
    function blockMarketplace(address marketplace) external onlyOwner{
        _blockedMarketplaces[marketplace] = true;
    }

    function allowMarketplace(address marketplace) external onlyOwner{
        _blockedMarketplaces[marketplace] = false;
    }
}

