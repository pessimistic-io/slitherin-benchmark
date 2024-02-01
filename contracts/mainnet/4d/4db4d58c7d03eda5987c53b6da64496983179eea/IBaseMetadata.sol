// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @title IBaseMetadata
/// @author Rohan Kulkarni
/// @notice The external Base Metadata errors and functions
interface IBaseMetadata {
    ///                                                          ///
    ///                            ERRORS                        ///
    ///                                                          ///

    /// @dev Reverts if the caller was not the contract manager
    error ONLY_MANAGER();

    ///                                                          ///
    ///                           FUNCTIONS                      ///
    ///                                                          ///

    /// @notice Initializes a DAO's token metadata renderer
    /// @param token The ERC721 token address
    /// @param initStrings The encoded token and metadata initialization strings
    function initialize(address token, bytes calldata initStrings) external;

    /// @notice Generates attributes for a token upon mint
    /// @param tokenId The ERC-721 token id
    function onMinted(uint256 tokenId) external returns (bool);

    /// @notice The token URI
    /// @param tokenId The ERC-721 token id
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /// @notice The contract URI
    function contractURI() external view returns (string memory);

    /// @notice The associated ERC-721 token
    function token() external view returns (address);

    /// @notice Get metadata owner address
    function owner() external view returns (address);
}

