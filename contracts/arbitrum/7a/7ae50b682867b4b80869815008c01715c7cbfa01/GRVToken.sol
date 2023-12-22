// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import "./BEP20Upgradeable.sol";

contract GRVToken is BEP20Upgradeable {
    /* ========== STATE VARIABLES ========== */

    mapping(address => bool) private _minters;

    /* ========== MODIFIERS ========== */

    modifier onlyMinter() {
        require(isMinter(msg.sender), "GRV: caller is not the minter");
        _;
    }

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __BEP20__init("Gravity Token", "GRV", 18);
        _minters[owner()] = true;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setMinter(address minter, bool canMint) external onlyOwner {
        _minters[minter] = canMint;
    }

    function mint(address _to, uint256 _amount) public onlyMinter {
        _mint(_to, _amount);
    }

    /* ========== VIEWS ========== */

    function isMinter(address account) public view returns (bool) {
        return _minters[account];
    }
}

