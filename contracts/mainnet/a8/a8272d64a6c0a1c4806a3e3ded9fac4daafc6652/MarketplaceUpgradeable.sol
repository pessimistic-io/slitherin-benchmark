// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ReentrancyGuardUpgradeable.sol";
import "./AdminControlUpgradeable.sol";
import "./MarketplaceCore.sol";

contract MarketplaceUpgradeable is AdminControlUpgradeable, MarketplaceCore, ReentrancyGuardUpgradeable {

    /**
     * Initializer
     */
    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        _setEnabled(true);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControlUpgradeable) returns (bool) {
        return interfaceId == type(IMarketplaceCore).interfaceId
            || AdminControlUpgradeable.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IMarketplace-setFees}.
     */
    function setFees(uint16 marketplaceFeeBPS, uint16 marketplaceReferrerBPS) external virtual override adminRequired {
        _setFees(marketplaceFeeBPS, marketplaceReferrerBPS);
    }
    
    /**
     * @dev See {IMarketplace-setEnabled}.
     */
    function setEnabled(bool enabled) external virtual override adminRequired {
        _setEnabled(enabled);
    }

    /**
     * @dev See {IMarketplace-setSellerRegistry}.
     */
    function setSellerRegistry(address registry) external virtual override adminRequired {
        _setSellerRegistry(registry);
    }

    /**
     * @dev See {IMarketplace-setRoyaltyEngineV1}.
     */
    function setRoyaltyEngineV1(address royaltyEngineV1) external virtual override adminRequired {
        _setRoyaltyEngineV1(royaltyEngineV1);
    }

    /**
     * @dev See {IMarketplace-cancel}.
     */
    function cancel(uint40 listingId, uint16 holdbackBPS) external virtual override nonReentrant {
        _cancel(listingId, holdbackBPS, isAdmin(msg.sender));
    }

    /**
     * @dev See {IMarketplace-withdraw}.
     */
    function withdraw(uint256 amount, address payable receiver) external virtual override adminRequired nonReentrant {
        _withdraw(address(0), amount, receiver);
    }

    /**
     * @dev See {IMarketplace-withdraw}.
     */
    function withdraw(address erc20, uint256 amount, address payable receiver) external virtual override adminRequired nonReentrant {
        _withdraw(erc20, amount, receiver);
    }

    /**
     * @dev See {IMarketplace-withdrawEscrow}.
     */
    function withdrawEscrow(uint256 amount) external virtual override nonReentrant {
        _withdrawEscrow(address(0), amount);
    }

    /**
     * @dev See {IMarketplace-withdrawEscrow}.
     */
    function withdrawEscrow(address erc20, uint256 amount) external virtual override nonReentrant {
        _withdrawEscrow(erc20, amount);
    }

    uint256[50] private __gap;

}
