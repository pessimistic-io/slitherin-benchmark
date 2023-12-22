// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
import "./Initializable.sol";

import "./_antiBotUpgradeable.sol";
import "./IAntiBot.sol";

contract AntibotBurnablePausableToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    _antiBotUpgradeable
{
    uint8 decimalDigits;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

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
        __Pausable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(PAUSER_ROLE, _owner);
        _mint(_minter, _totalSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return decimalDigits;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(_antiBotUpgradeable, ERC20Upgradeable) {
        super._afterTokenTransfer(from, to, amount);
    }

}

