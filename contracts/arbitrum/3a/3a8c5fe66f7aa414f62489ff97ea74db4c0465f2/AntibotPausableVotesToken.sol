// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
import "./ERC20VotesUpgradeable.sol";
import "./Initializable.sol";
import "./_antiBotUpgradeable.sol";
import "./IAntiBot.sol";

contract AntibotPausableVotesToken is
    Initializable,
    ERC20Upgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
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
        __Pausable_init();
        __AccessControl_init();
        
        __ERC20Votes_init();
        __ERC20Permit_init(_name);
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


   
      // The following functions are overrides required by Solidity.


    function _mint(address account, uint256 amount)
        internal
        virtual
        override( ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._mint(account, amount);
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
    ) internal override(_antiBotUpgradeable, ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._afterTokenTransfer(from, to, amount);
    }

   
    function _burn(address account, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._burn(account, amount);
    }
}

