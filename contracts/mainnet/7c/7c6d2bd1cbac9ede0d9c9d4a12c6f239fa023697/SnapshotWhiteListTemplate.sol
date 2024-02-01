// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Base.sol";
import "./SnapshotFeature.sol";
import "./PausableWithWhitelistFeature.sol";

contract SnapshotWhiteListTemplate is
    SnapshotFeature,
    PausableWithWhitelistFeature
{
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 amount_
    ) public initializer {
        __ERC20Base_init(name_, symbol_, decimals_, amount_);
    }

    function _beforeTokenTransfer_hook(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(SnapshotFeature, PausableWithWhitelistFeature) {
        SnapshotFeature._beforeTokenTransfer_hook(from, to, amount);
        PausableWithWhitelistFeature._beforeTokenTransfer_hook(
            from,
            to,
            amount
        );
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20SnapshotRewrited, ERC20Upgradeable) {
        _beforeTokenTransfer_hook(from, to, amount);
        super._beforeTokenTransfer(from, to, amount);
    }
}

