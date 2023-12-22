// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ERC20.sol";
import "./AccessControlEnumerable.sol";

import "./ILayV1Token.sol";

contract layV1Token is IlayV1Token, AccessControlEnumerable, ERC20("lay", "LL") {
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "ERC20: !minter");
        _;
    }

    modifier onlyBurner() {
        require(hasRole(BURNER_ROLE, msg.sender), "ERC20: !burner");
        _;
    }

    function mint(address _recipient, uint256 _amount) external onlyMinter {
        _mint(_recipient, _amount);
    }

    function burn(uint256 _amount) external onlyBurner {
        _burn(msg.sender, _amount);
    }
}

