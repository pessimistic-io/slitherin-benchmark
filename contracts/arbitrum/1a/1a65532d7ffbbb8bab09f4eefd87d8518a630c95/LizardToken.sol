// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./ERC20.sol";

/// @title Lizard Token
/// @author LI.FI (https://li.fi)
/// @notice LizardDAO Rewards Token
contract LizardToken is ERC20 {
    /// State ///

    uint8 public constant CAN_MINT = 1; // 00000001
    uint8 public constant CAN_BURN = 2; // 00000010

    mapping(address => uint8) public permissions;

    address public owner;

    uint256 public MAX_MINTABLE_TOKENS = 20_000_000 * 10**18;

    /// Errors ///

    error MethodDisallowed();
    error InvalidMintAmount();
    error InvalidBurnAmount();

    /// Events ///

    event SetCanMint(address indexed user);
    event UnsetCanMint(address indexed user);
    event SetCanBurn(address indexed user);
    event UnsetCanBurn(address indexed user);
    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );

    /// Constructor
    constructor() ERC20("Lizard Token", "LZRD", 18) {
        owner = msg.sender;
        permissions[msg.sender] = CAN_MINT | CAN_BURN;
    }

    /// @notice award tokens to a specific address
    /// @param to the address to award tokens to
    /// @param amount the amount of tokens to award
    function awardTokens(address to, uint256 amount) external {
        if (permissions[msg.sender] & CAN_MINT != CAN_MINT)
            revert MethodDisallowed();
        if (amount + totalSupply > MAX_MINTABLE_TOKENS)
            revert InvalidMintAmount();

        _mint(to, amount);
    }

    /// @notice burns tokens from an address
    /// @param from the address to burn tokens from
    /// @param amount the amount of tokens to burn
    function burnTokens(address from, uint256 amount) external {
        if (permissions[msg.sender] & CAN_BURN != CAN_BURN)
            revert MethodDisallowed();
        if (amount > balanceOf[from]) revert InvalidBurnAmount();

        _burn(from, amount);
    }

    /// @notice sets the mint permission
    /// @param user the address to give minting permission to
    function setCanMint(address user) external {
        if (msg.sender != owner) revert MethodDisallowed();
        permissions[user] |= CAN_MINT;
        emit SetCanMint(user);
    }

    /// @notice sets the burn permission
    /// @param user the address to give burn permission to
    function unsetCanMint(address user) external {
        if (msg.sender != owner) revert MethodDisallowed();
        permissions[user] &= ~CAN_MINT;
        emit UnsetCanMint(user);
    }

    /// @notice unsets the mint permission
    /// @param user the address to remove mint permission from
    function unsetCanBurn(address user) external {
        if (msg.sender != owner) revert MethodDisallowed();
        permissions[user] &= ~CAN_BURN;
        emit UnsetCanBurn(user);
    }

    /// @notice unsets the burn permission
    /// @param user the address to remove burn permission from
    function setCanBurn(address user) external {
        if (msg.sender != owner) revert MethodDisallowed();
        permissions[user] |= CAN_BURN;
        emit SetCanBurn(user);
    }

    /// @notice transfers ownership of the contract to a new address
    /// @param newOwner the address to transfer ownership to
    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert MethodDisallowed();
        owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }

    /// ⚠️ Disallowed  Methods ⚠️ ///

    function approve(address, uint256) public pure override returns (bool) {
        revert MethodDisallowed();
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert MethodDisallowed();
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert MethodDisallowed();
    }

    function permit(
        address,
        address,
        uint256,
        uint256,
        uint8,
        bytes32,
        bytes32
    ) public pure override {
        revert MethodDisallowed();
    }
}

