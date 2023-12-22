// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./_antiBotUpgradeable.sol";
import "./IAntiBot.sol";

contract AntibotBurnableToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    _antiBotUpgradeable
{
    uint8 decimalDigits;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _totalSupply,
        address _minter,
        IAntiBot _antiBotAddress
    ) public initializer {
        decimalDigits = _decimals;
        __Antibot_init_unchained(_antiBotAddress, _owner);
        __ERC20_init(_name, _symbol);
        __ERC20Burnable_init();
        _mint(_minter, _totalSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return decimalDigits;
    }

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Upgradeable, _antiBotUpgradeable) {
        super._afterTokenTransfer(from, to, amount);
    }
}

