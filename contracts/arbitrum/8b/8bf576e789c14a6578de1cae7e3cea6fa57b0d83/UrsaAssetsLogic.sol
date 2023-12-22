// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import {Assets} from "./Assets.sol";

contract UrsaAssetsLogic is
    Assets,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    ////////////////////////////////////////////////////////////////////////////
    // INITIALIZER
    ////////////////////////////////////////////////////////////////////////////

    function initialize() external initializer {
        __Assets_init(
            "https://ursa-cdn.pages.dev/metadata/{id}.json",
            "URSA Assets",
            "UrsaAssets"
        );
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    ////////////////////////////////////////////////////////////////////////////
    // MODIFIERS
    ////////////////////////////////////////////////////////////////////////////

    modifier onlyEOA() {
        require(tx.origin == msg.sender, "Forbidden");
        _;
    }

    ////////////////////////////////////////////////////////////////////////////
    // OWNER
    ////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Pause minting.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause minting.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    ////////////////////////////////////////////////////////////////////////////
    // OVERRIDES
    ////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Mint an asset.
     */
    function mint(
        address __account,
        uint256 __id,
        uint256 __amount
    ) external override nonReentrant whenNotPaused {
        require(
            hasRole(MINTER_ROLE, msg.sender) || __account == msg.sender,
            "Forbidden"
        );

        _mintToken(__account, __id, __amount);
    }

    ////////////////////////////////////////////////////////////////////////////
    // UPGRADEABLE
    ////////////////////////////////////////////////////////////////////////////

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

