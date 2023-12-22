// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import { ERC20 } from "./ERC20.sol";

// Token for Tournaments. Includes initial mint function and burn function
// Token is pausable
contract TournamentToken is ERC20 {
    mapping(address => mapping(address => bool)) public transferWhitelist;
    address public owner;
    string internal _name;
    string internal _symbol;

    bool initialized;
    bool public isPaused;

    constructor() ERC20("Tournament", "TT") {}

    function initialize(
        uint256 initialBalance,
        string memory name_,
        string memory symbol_
    ) external {
        require(!initialized, "already initialized");
        initialized = true;
        owner = msg.sender;
        _name = name_;
        _symbol = symbol_;
        _mint(owner, initialBalance);
    }

    event PauseStatusChanged(bool status);
    event WhiteListStatusChanged(address indexed from, address indexed to, bool status);

    modifier onlyOwner {
        require(msg.sender == owner, "onlyOwner: sender is not owner");
        _;
    }

    // @dev Set pause status. Only owner
    function setPauseStatus(bool status) external onlyOwner {
        isPaused = status;
        emit PauseStatusChanged(status);
    }

    // @dev Set whitelist status between two accounts
    function setWhitelistStatus(address from, address to, bool status) external onlyOwner {
        transferWhitelist[from][to] = status;
        emit WhiteListStatusChanged(from, to, status);
    }

    // @dev If paused, revert transaction for non-whitelisted transfers
    function _beforeTokenTransfer(address from, address to, uint256 /*amount*/) internal override view {
        if (!isPaused) {
            return;
        }
        else { 
            require(transferWhitelist[from][to], "_beforeTokenTransfer: transfers paused"); 
        }
    }

    /**
     * @dev Burn tokens from sender
     */
    function burn(uint256 amount) external virtual {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }
}

