// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Snapshot.sol";
import "./AccessControlEnumerable.sol";
import "./draft-ERC20Permit.sol";
import "./ERC20Votes.sol";
import "./ERC20Capped.sol";

/*
    :::      ::::::::   ::::::::  :::::::::: ::::    :::  :::::::: ::::::::::: ::::::::  ::::    :::
  :+: :+:   :+:    :+: :+:    :+: :+:        :+:+:   :+: :+:    :+:    :+:    :+:    :+: :+:+:   :+:
 +:+   +:+  +:+        +:+        +:+        :+:+:+  +:+ +:+           +:+    +:+    +:+ :+:+:+  +:+
+#++:++#++: +#++:++#++ +#+        +#++:++#   +#+ +:+ +#+ +#++:++#++    +#+    +#+    +:+ +#+ +:+ +#+
+#+     +#+        +#+ +#+        +#+        +#+  +#+#+#        +#+    +#+    +#+    +#+ +#+  +#+#+#
#+#     #+# #+#    #+# #+#    #+# #+#        #+#   #+#+# #+#    #+#    #+#    #+#    #+# #+#   #+#+#
###     ###  ########   ########  ########## ###    ####  ######## ########### ########  ###    ####
:::::::::  :::::::::   :::::::: ::::::::::: ::::::::   ::::::::   ::::::::  :::
:+:    :+: :+:    :+: :+:    :+:    :+:    :+:    :+: :+:    :+: :+:    :+: :+:
+:+    +:+ +:+    +:+ +:+    +:+    +:+    +:+    +:+ +:+        +:+    +:+ +:+
+#++:++#+  +#++:++#:  +#+    +:+    +#+    +#+    +:+ +#+        +#+    +:+ +#+
+#+        +#+    +#+ +#+    +#+    +#+    +#+    +#+ +#+        +#+    +#+ +#+
#+#        #+#    #+# #+#    #+#    #+#    #+#    #+# #+#    #+# #+#    #+# #+#
###        ###    ###  ########     ###     ########   ########   ########  ##########
 */
contract AscensionToken is
    ERC20,
    ERC20Burnable,
    ERC20Capped,
    ERC20Snapshot,
    AccessControlEnumerable,
    ERC20Permit,
    ERC20Votes
{
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20("Ascension Protocol", "ASCEND") ERC20Permit("Ascension Protocol") ERC20Capped(14_400_000e18) {
        //default admin role to deployer
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        //snapshot role to deployer
        _setupRole(SNAPSHOT_ROLE, _msgSender());
        // total supply to deployer
        _mint(_msgSender(), 14_400_000e18);
    }

    function snapshot() external onlyRole(SNAPSHOT_ROLE) returns (uint256) {
        uint256 id = _snapshot();
        return id;
    }

    function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Snapshot) {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes, ERC20Capped) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}

