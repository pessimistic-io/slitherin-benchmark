// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {TokenFactoryStorage} from "./TokenFactoryStorage.sol";

interface ITokenFactory {
    enum TokenStandard {
        ERC20,
        ERC721,
        ERC1155
    }

    event ERC20Created(address indexed token);
    event ERC721Created(address indexed token);
    event ERC1155Created(address indexed token);
    event ImplementationSet(address indexed newImplementation, TokenStandard indexed standard);

    error InvalidImplementation();

    /// @dev Initializes the proxy for the factory
    /// @param owner_ The owner address to be set for the factory contract
    function initialize(address owner_, address erc20Impl_, address erc721Impl_, address erc1155Impl_) external;

    /// @dev Function to create a new ERC20 token proxy using given data
    /// @param implementation The logic implementation address to be set for the created proxy
    /// @param inputSalt A 32-byte salt to enable consistent addresses across chains and prevent collision
    /// @param owner The owner address to be set for the new token proxy
    /// @param name The token name string
    /// @param symbol The token symbol string
    /// @param initData Data to pass to `initialize()` on the created token proxy
    /// @return token The created token proxy address
    function createERC20(
        address payable implementation,
        bytes32 inputSalt,
        address owner,
        string memory name,
        string memory symbol,
        bytes calldata initData
    ) external returns (address payable token);

    /// @dev Function to create a new ERC721 token proxy using given data
    /// @param implementation The logic implementation address to be set for the created proxy
    /// @param inputSalt A 32-byte salt to enable consistent addresses across chains and prevent collision
    /// @param owner The owner address to be set for the new token proxy
    /// @param name The token name string
    /// @param symbol The token symbol string
    /// @param initData Data to pass to `initialize()` on the created token proxy
    /// @return token The created token proxy address
    function createERC721(
        address payable implementation,
        bytes32 inputSalt,
        address owner,
        string memory name,
        string memory symbol,
        bytes calldata initData
    ) external returns (address payable token);

    /// @dev Function to create a new ERC1155 token proxy using given data
    /// @param implementation The logic implementation address to be set for the created proxy
    /// @param inputSalt A 32-byte salt to enable consistent addresses across chains and prevent collision
    /// @param owner The owner address to be set for the new token proxy
    /// @param name The token name string
    /// @param symbol The token symbol string
    /// @param initData Data to pass to `initialize()` on the created token proxy
    /// @return token The created token proxy address
    function createERC1155(
        address payable implementation,
        bytes32 inputSalt,
        address owner,
        string memory name,
        string memory symbol,
        bytes calldata initData
    ) external returns (address payable token);

    /// @dev Function to add a recognized token implementation (packed with its ERC standard enum)
    function addImplementation(TokenFactoryStorage.TokenImpl memory tokenImpl) external;
    /// @dev Function to remove a recognized token implementation (packed with its ERC standard enum)
    function removeImplementation(TokenFactoryStorage.TokenImpl memory tokenImpl) external;
}

