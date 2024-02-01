// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC721Votes} from "./IERC721Votes.sol";
import {TokenTypesV1} from "./TokenTypesV1.sol";
import {TokenTypesV2} from "./TokenTypesV2.sol";

/// @title IToken
/// @author Rohan Kulkarni
/// @notice The external Token events, errors and functions
interface IToken is IERC721Votes, TokenTypesV1, TokenTypesV2 {
    ///                                                          ///
    ///                            EVENTS                        ///
    ///                                                          ///

    /// @notice Emitted when minters are updated
    /// @param minter Address of added or removed minter
    /// @param allowed Whether address is allowed to mint
    event MinterUpdated(address minter, bool allowed);

    ///                                                          ///
    ///                            ERRORS                        ///
    ///                                                          ///

    /// @dev Reverts if the caller was not the auction contract
    error ONLY_AUCTION();

    /// @dev Reverts if the caller was not a minter
    error ONLY_AUCTION_OR_MINTER();

    /// @dev Reverts if the caller was not the token owner
    error ONLY_TOKEN_OWNER();

    /// @dev Reverts if no metadata was generated upon mint
    error NO_METADATA_GENERATED();

    /// @dev Reverts if the caller was not the contract manager
    error ONLY_MANAGER();

    ///                                                          ///
    ///                           FUNCTIONS                      ///
    ///                                                          ///

    /// @notice Initializes a DAO's ERC-721 token
    /// @param initStrings The encoded token and metadata initialization strings
    /// @param treasury The treasury
    function initialize(bytes calldata initStrings, address treasury) external;

    /// @notice Mints tokens to the caller and handles treasury vesting
    function mint() external returns (uint256 tokenId);

    /// @notice Mints tokens to the recipient and handles treasury vesting
    function mintTo(address recipient) external returns (uint256 tokenId);

    /// @notice Mints the specified amount of tokens to the recipient and handles treasury vesting
    function mintBatchTo(
        uint256 amount,
        address recipient
    ) external returns (uint256[] memory tokenIds);

    /// @notice Burns a token owned by the caller
    /// @param tokenId The ERC-721 token id
    function burn(uint256 tokenId) external;

    /// @notice The URI for a token
    /// @param tokenId The ERC-721 token id
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /// @notice The URI for the contract
    function contractURI() external view returns (string memory);

    /// @notice The total supply of tokens
    function totalSupply() external view returns (uint256);

    /// @notice The token's auction house
    function auction() external view returns (address);

    /// @notice The token's metadata renderer
    function metadataRenderer() external view returns (address);

    /// @notice The owner of the token and metadata renderer
    function owner() external view returns (address);

    /// @notice Update minters
    /// @param _minters Array of structs containing address status as a minter
    function updateMinters(MinterParams[] calldata _minters) external;

    /// @notice Check if an address is a minter
    /// @param _minter Address to check
    function isMinter(address _minter) external view returns (bool);

    /// @notice Callback called by auction on first auction started to transfer ownership to treasury from deployer
    function onFirstAuctionStarted() external;
}

