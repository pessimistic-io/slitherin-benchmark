// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./Initializable.sol";

/**
 * @title Kunji
 * @dev A claimable ERC20 token contract
 */
contract Kunji is Initializable, OwnableUpgradeable, ERC20Upgradeable {

    uint256 constant MAX_TOTAL_SUPPLY = 2500000e18;

    mapping(address => bool) public hasClaimed;
    uint256 public claimEndDate;
    uint256 public tokensPerClaim;
    mapping(address => bool) public whitelist;

    uint256[50] private __gaps;

    event TokensClaimed(address indexed account, uint256 amount);
    event ClaimEndDateSet(uint256 endDate);
    event TokensPerClaimSet(uint256 amount);
    event WhitelistUpdated(address indexed account, bool isWhitelisted);

    /**
     * @dev Initializes the contract by setting the default claim end date and tokens per claim
     * @param name The name of the token
     * @param symbol The symbol of the token
     */
    function initialize(string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        __Ownable_init();
        claimEndDate = block.timestamp + 30 days; // default to 30 days from deployment
        tokensPerClaim = 100e18; // default to 100 tokens per claim
    }

    /**
     * @dev Allows a user to claim tokens if they have not already claimed and claim period is still open
     */
    function claimTokens() public {
        require(!hasClaimed[msg.sender], "Tokens already minted! Minting limit reached.");
        require(block.timestamp <= claimEndDate, "Program closed. Thank you for your support!");
        require(totalSupply() <= MAX_TOTAL_SUPPLY,"All tokens minted. No more available. Thank you!");

        hasClaimed[msg.sender] = true;
        _mint(msg.sender, tokensPerClaim); // mint the set amount of tokens
        emit TokensClaimed(msg.sender, tokensPerClaim); // emit an event to indicate tokens claimed
    }

    /**
     * @dev Allows the owner to set the end date of the claim period
     * @param endDate The new end date for the claim period
     */
    function setClaimEndDate(uint256 endDate) public onlyOwner {
        claimEndDate = endDate;
        emit ClaimEndDateSet(endDate); // emit an event to indicate end date updated
    }

    /**
     * @dev Allows the owner to set the amount of tokens to be minted on claim
     * @param amount The new amount of tokens to be minted on claim
     */
    function setTokensPerClaim(uint256 amount) public onlyOwner {
        tokensPerClaim = amount;
        emit TokensPerClaimSet(amount); // emit an event to indicate tokens per claim updated
    }

    /**
     * @dev Allows the owner to add or remove an address from the whitelist
     * @param account The address to be added or removed from the whitelist
     * @param isWhitelisted A boolean indicating whether the address should be whitelisted or not
     */
    function updateWhitelist(address account, bool isWhitelisted) public onlyOwner {
        whitelist[account] = isWhitelisted;
        emit WhitelistUpdated(account, isWhitelisted); // emit an event to indicate whitelist updated
    }
    
    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning, as well as transfer and transferFrom functions.
     *
     * Checks that the `msg.sender` is whitelisted before allowing the transfer to proceed.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        require(from == address(0) || whitelist[msg.sender], "Sender not whitelisted");
    }

}

