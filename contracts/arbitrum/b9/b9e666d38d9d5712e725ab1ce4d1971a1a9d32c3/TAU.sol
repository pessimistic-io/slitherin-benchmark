// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "./ERC20.sol";
import { ERC20Burnable } from "./ERC20Burnable.sol";
import { Ownable } from "./Ownable.sol";

error notGovernance();
error mintLimitExceeded(uint256 newAmount, uint256 maxMintAmount);

contract TAU is ERC20, ERC20Burnable, Ownable {
    // Max amount of tokens which a given vault can mint. Since this is set to zero by default, there is no need to register vaults.
    mapping(address => uint256) public mintLimit;
    mapping(address => uint256) public currentMinted;

    constructor() ERC20("TAU", "TAU") {}

    /**
     * @dev Set new mint limit for a given vault. Only governance can call this function.
     * note if the new limit is lower than the vault's current amount minted, this will disable future mints for that vault,
        but will do nothing to its existing minted amount.
     * @param vault The address of the vault whose mintLimit will be updated
     * @param newLimit The new mint limit for the target vault
     */
    function setMintLimit(address vault, uint256 newLimit) external onlyOwner {
        mintLimit[vault] = newLimit;
    }

    function mint(address recipient, uint256 amount) external {
        // Check whether mint amount exceeds mintLimit for msg.sender
        uint256 newMinted = currentMinted[msg.sender] + amount;
        if (newMinted > mintLimit[msg.sender]) {
            revert mintLimitExceeded(newMinted, mintLimit[msg.sender]);
        }

        // Update vault currentMinted
        currentMinted[msg.sender] = newMinted;

        // Mint TAU to recipient
        _mint(recipient, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual override {
        address account = _msgSender();
        _burn(account, amount);
        _decreaseCurrentMinted(amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance. Also decreases the burner's currentMinted amount if the burner is a vault.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount) public virtual override {
        super.burnFrom(account, amount);
        _decreaseCurrentMinted(amount);
    }

    function _decreaseCurrentMinted(uint256 amount) internal virtual {
        address account = _msgSender();
        // If the burner is a vault, subtract burnt TAU from its currentMinted.
        // This has a few highly unimportant edge cases which can generally be rectified by increasing the relevant vault's mintLimit.
        uint256 accountMinted = currentMinted[account];
        if (accountMinted >= amount) {
            currentMinted[account] = accountMinted - amount;
        }
    }
}

