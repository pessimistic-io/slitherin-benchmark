// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20Upgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
import "./ERC20VotesUpgradeable.sol";
import "./Initializable.sol";
import "./ERC20CappedUpgradeable.sol";

contract CappedVotesToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    ERC20CappedUpgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable
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
        uint256 _totalSupply
    ) public initializer {
        decimalDigits = _decimals;
        __ERC20_init(_name, _symbol);
        __AccessControl_init();
        
        __ERC20Capped_init(_totalSupply);
        __ERC20Votes_init();
        __ERC20Permit_init(_name);
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(MINTER_ROLE, _owner);
    }


    function decimals() public view virtual override returns (uint8) {
        return decimalDigits;
    }

   
      // The following functions are overrides required by Solidity.


    function _mint(address account, uint256 amount)
        internal
        virtual
        override(ERC20CappedUpgradeable, ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._mint(account, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override( ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._afterTokenTransfer(from, to, amount);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

  
    function _burn(address account, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._burn(account, amount);
    }
}

