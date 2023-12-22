pragma solidity ^0.8.7;

import "./AccessControlEnumerable.sol";
import "./ERC20Burnable.sol";
import "./ERC20Capped.sol";
import "./draft-ERC20Permit.sol";

contract RelayToken is ERC20Burnable, ERC20Permit, AccessControlEnumerable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(
        address owner,
        string memory name,
        string memory symbol
    ) ERC20Permit(name) ERC20(name, symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, owner);
        _setupRole(MINTER_ROLE, owner);
    }

    function mint(address account, uint256 amount) public {
        require(hasRole(MINTER_ROLE, _msgSender()), "RelayToken: must have minter role to mint");
        _mint(account, amount);
    }
}
