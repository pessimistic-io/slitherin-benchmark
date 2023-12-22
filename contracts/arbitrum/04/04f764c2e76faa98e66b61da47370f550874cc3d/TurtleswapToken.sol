// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./draft-ERC20Permit.sol";
import "./ERC20Burnable.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";

contract TurtleswapToken is
    ERC20Burnable,
    ERC20Permit,
    AccessControl,
    Pausable
{
    using SafeERC20 for IERC20;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant RESCUER_ROLE = keccak256("RESCUER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 internal MAX_TOTAL_SUPPLY = 10000000 ether;

    constructor() ERC20("Turtleswap Token", "TURTL") ERC20Permit("Turtl") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
        _setupRole(RESCUER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        require(
            amount + totalSupply() <= MAX_TOTAL_SUPPLY,
            "Cant mint more than max supply"
        );
        _mint(to, amount);
    }

    function getMaxTotalSupply() external view returns (uint256) {
        return MAX_TOTAL_SUPPLY;
    }

    function rescueTokens(IERC20 token, uint256 value)
        external
        onlyRole(RESCUER_ROLE)
    {
        token.transfer(msg.sender, value);
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
}

