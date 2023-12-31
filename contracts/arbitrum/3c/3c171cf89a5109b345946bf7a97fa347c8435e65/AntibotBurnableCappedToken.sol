// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./ERC20CappedUpgradeable.sol";
import "./_antiBotUpgradeable.sol";
import "./IAntiBot.sol";

contract AntibotBurnableCappedToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    AccessControlUpgradeable,
    ERC20CappedUpgradeable,
    _antiBotUpgradeable
{
    uint8 decimalDigits;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

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
        IAntiBot _antiBotAddress
    ) public initializer {
        decimalDigits = _decimals;
        __Antibot_init_unchained(_antiBotAddress, _owner);
        __ERC20_init(_name, _symbol);
        __ERC20Burnable_init();
        __AccessControl_init();
        __ERC20Capped_init(_totalSupply);
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(MINTER_ROLE, _owner);
    }

    function decimals() public view virtual override returns (uint8) {
        return decimalDigits;
    }

  
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(_antiBotUpgradeable, ERC20Upgradeable) {
        super._afterTokenTransfer(from, to, amount);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function _mint(address account, uint256 amount)
        internal
        virtual
        override(ERC20CappedUpgradeable, ERC20Upgradeable)
    {
        super._mint(account, amount);
    }
}

