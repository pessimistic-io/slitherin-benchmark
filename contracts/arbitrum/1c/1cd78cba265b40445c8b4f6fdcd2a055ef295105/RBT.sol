// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20CappedUpgradeable, ERC20Upgradeable} from "./ERC20CappedUpgradeable.sol";
import {SafeOwnableUpgradeable} from "./utils_SafeOwnableUpgradeable.sol";
import {UUPSUpgradeable} from "./utils_UUPSUpgradeable.sol";
import {ERC20PermitUpgradeable} from "./draft-ERC20PermitUpgradeable.sol";
import {ERC20BurnableUpgradeable} from "./ERC20BurnableUpgradeable.sol";
import {IRebornToken} from "./IRebornToken.sol";
import {RBTStorage} from "./RBTStorage.sol";

contract RBT is
    ERC20PermitUpgradeable,
    ERC20CappedUpgradeable,
    SafeOwnableUpgradeable,
    UUPSUpgradeable,
    IRebornToken,
    RBTStorage,
    ERC20BurnableUpgradeable
{
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 cap_,
        address owner_
    ) public initializer {
        __ERC20_init_unchained(name_, symbol_);
        __ERC20Capped_init(cap_);
        __ERC20Permit_init(name_);
        __Ownable_init(owner_);
    }

    // directly revert upgrade
    function _authorizeUpgrade(address) internal override onlyOwner {
        revert CannotUpgradeAnyMore();
    }

    /**
     * @dev allow minter to mint it
     */
    function mint(address to, uint256 amount) external override onlyMinter {
        _mint(to, amount);
    }

    /**
     * @dev update minters
     */
    function updateMinter(
        address[] calldata toAdd,
        address[] calldata toRemove
    ) external onlyOwner {
        for (uint256 i = 0; i < toAdd.length; i++) {
            minters[toAdd[i]] = true;
            emit MinterUpdate(toAdd[i], true);
        }
        for (uint256 i = 0; i < toRemove.length; i++) {
            delete minters[toRemove[i]];
            emit MinterUpdate(toRemove[i], false);
        }
    }

    /**
     * @dev See {ERC20-_mint}.
     */
    function _mint(
        address account,
        uint256 amount
    ) internal virtual override(ERC20CappedUpgradeable, ERC20Upgradeable) {
        require(
            ERC20Upgradeable.totalSupply() + amount <= cap(),
            "ERC20Capped: cap exceeded"
        );
        ERC20Upgradeable._mint(account, amount);
    }

    modifier onlyMinter() {
        if (!minters[msg.sender]) {
            revert NotMinter();
        }
        _;
    }
}

