// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IBurnPool} from "./IBurnPool.sol";
import {Ownable} from "./Ownable.sol";
import {IRebornToken} from "./IRebornToken.sol";
import {ERC20BurnableUpgradeable} from "./ERC20BurnableUpgradeable.sol";

contract BurnPool is IBurnPool, Ownable {
    IRebornToken rebornToken;

    constructor(address owner_, address rebornToken_) {
        if (owner_ == address(0)) {
            revert ZeroOwnerSet();
        }

        if (rebornToken_ == address(0)) {
            revert ZeroRebornTokenSet();
        }

        _transferOwnership(owner_);
        rebornToken = IRebornToken(rebornToken_);
    }

    function burn(uint256 amount) external override onlyOwner {
        ERC20BurnableUpgradeable(address(rebornToken)).burn(amount);

        emit Burn(amount);
    }
}

