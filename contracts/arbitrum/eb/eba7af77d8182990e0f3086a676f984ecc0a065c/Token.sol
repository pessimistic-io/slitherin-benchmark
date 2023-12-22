// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./draft-ERC20Permit.sol";
import "./ERC20Votes.sol";
import "./Ownable.sol";
import "./Address.sol";

import "./TaxCollector.sol";

/// @title DaikokuDAO
/// @dev A detailed ERC20 token with burn, permit and voting capabilities. Includes a tax mechanism.
contract DaikokuDAO is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes, Ownable {
    TaxCollector public taxCollectorContract;
    mapping(address => bool) public untaxedAddresses;
    uint256 constant TAX_RATE_CAP = 10;
    uint256 public taxRate = 10;
    bool public isTaxActive = true;

    address public minter;  // add a minter state variable

    // 100 million tokens. This is a practical (but arbitrary) maximum.
    // It's the equivalent of raising 100 million at $1 per DKKU.
    uint256 private constant MAX_SUPPLY = 100_000_000 * 10 ** 18;

    /// @dev Constructor sets the minter to the contract deployer.
    constructor() ERC20("Daikoku DAO", "DKKU") ERC20Permit("Daikoku DAO") {
        minter = msg.sender;  // initially set the contract deployer as the minter
    }

    /// @notice Mint new tokens
    /// @dev Can only be called by the current minter.
    /// @param to Address to send the newly minted tokens to.
    /// @param amount Amount of tokens to mint.
    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "Caller is not the minter");  // only allow the minter to mint
        require(to != address(0), "Cannot mint to zero address");
	require(totalSupply() + amount <= MAX_SUPPLY, "Minting exceeds max supply");
        _mint(to, amount);
    }

    /// @notice Change the minter
    /// @dev Can only be called by the owner.
    /// @param _minter Address to set as the new minter.
    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "Cannot set the zero address");
        minter = _minter;
    }

    /// @dev Overrides ERC20._transfer() to implement tax functionality.
    function _transfer(address sender, address recipient, uint256 amount)
        internal
        override(ERC20)
    {
        if (!isTaxActive) {
            super._transfer(sender, recipient, amount);
        } else {
            uint256 taxAmount = amount * taxRate / 100;
            uint256 netAmount = amount - taxAmount;
	    super._transfer(sender, recipient, netAmount);

	    super._transfer(sender, address(taxCollectorContract), taxAmount);
	    taxCollectorContract.distributeCollectedTax(taxAmount);
        }
    }

    //
    // Tax
    //

    /// @notice Set the tax collector contract
    /// @dev Can only be called by the owner.
    /// @param _taxCollectorContract Address of the tax collector contract.
    function setTaxCollector(address payable _taxCollectorContract) external onlyOwner {
	require(_taxCollectorContract != address(0), "Invalid tax collector address");
	require(Address.isContract(_taxCollectorContract), "TaxCollector must be a contract");

        taxCollectorContract = TaxCollector(_taxCollectorContract);
	untaxedAddresses[_taxCollectorContract] = true;
    }

    /// @notice Toggle the tax
    /// @dev Can only be called by the owner.
    function toggleTax() external onlyOwner {
	isTaxActive = !isTaxActive;
    }

    /// @notice Set the tax rate
    /// @dev Can only be called by the owner.
    /// @param _taxRate The new tax rate (must be <= 10%).
    function setTaxRate(uint256 _taxRate) external onlyOwner {
	require(_taxRate <= TAX_RATE_CAP, "tax must be <= 10%");
	taxRate = _taxRate;
    }

    /// @notice Add addresses to the untaxed list
    /// @dev Can only be called by the owner.
    /// @param addresses List of addresses to be added to the untaxed list.
    function addUntaxedAddresses(address[] memory addresses) external onlyOwner {
        for (uint i = 0; i < addresses.length; ++i) {
            untaxedAddresses[addresses[i]] = true;
        }
    }

    /// @notice Remove addresses from the untaxed list
    /// @dev Can only be called by the owner.
    /// @param addresses List of addresses to be removed from the untaxed list.
    function removeUntaxedAddresses(address[] memory addresses) external onlyOwner {
        for (uint i = 0; i < addresses.length; ++i) {
            untaxedAddresses[addresses[i]] = false;
        }
    }

    /// @notice Transfer tokens without applying tax
    /// @dev Can only be called by addresses in the untaxed list or the owner.
    /// @param sender The address to send tokens from.
    /// @param recipient The address to send tokens to.
    /// @param amount The amount of tokens to send.
    function transferWithoutTax(address sender, address recipient, uint256 amount) external {
        require(untaxedAddresses[sender] || sender == owner(), "Cannot transfer without tax");
        super._transfer(sender, recipient, amount);
    }

    //
    // The following functions are overrides required by Solidity.
    //

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}

