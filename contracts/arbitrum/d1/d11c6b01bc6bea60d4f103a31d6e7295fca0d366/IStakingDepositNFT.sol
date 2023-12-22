// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./introspection_IERC165Upgradeable.sol";
import "./IERC721EnumerableUpgradeable.sol";

import "./IStakingDepositNFTDesign.sol";
import "./IUnlimitedStaking.sol";

/// @title IStakingDepositNFT interface for ERC721 staking deposit NFTs
/// @notice This contract defines the interface for staking deposit NFTs, which represent locked tokens in a staking contract.
interface IStakingDepositNFT is
    IERC165Upgradeable,
    IERC721EnumerableUpgradeable
{
    /// ERC165 bytes to add to interface array - set in parent contract
    ///
    /// _INTERFACE_ID_ERC4494 = 0x5604e225

    /// @notice Approves a spender to transfer an NFT on behalf of the owner, using a signed permit.
    /// @param spender The address to approve as a spender.
    /// @param tokenId The ID of the NFT to approve the spender on.
    /// @param deadline A timestamp that specifies the permit's expiration.
    /// @param sig A traditional or EIP-2098 signature.
    function permit(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        bytes memory sig
    ) external;

    /// @notice Returns the nonce of an NFT, which is useful for creating permits.
    /// @param tokenId The ID of the NFT to get the nonce of.
    /// @return The uint256 representation of the nonce.
    function nonces(uint256 tokenId) external view returns (uint256);

    /// @notice Returns the domain separator used in the encoding of the signature for permits, as defined by EIP-712.
    /// @return The bytes32 domain separator.
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice Updates the NFT design with a new design.
    /// @param newValue The new design for the NFT.
    function updateDesign(IStakingDepositNFTDesign newValue) external;

    /// @notice Sets the UWUStaking contract.
    /// @param unlimitedStaking The UnlimitedStaking contract.
    function setUWUStaking(IUnlimitedStaking unlimitedStaking) external;

    /// @notice Updates the design decimals with a new value.
    /// @param newValue The new value for the design decimals.
    function updateDesignDecimals(uint8 newValue) external;

    /// @notice Mints a new NFT.
    /// @param to The address to mint the NFT to.
    /// @param tokenId The ID of the NFT to be minted.
    function mint(address to, uint tokenId) external;

    /// @notice Burns an existing NFT.
    /// @param tokenId The ID of the NFT to be burned.
    function burn(uint tokenId) external;

    /**
     * @notice Safe permit and transfer from.
     * @param from The address to approve as a spender.
     * @param to The address to approve as a spender.
     * @param tokenId The ID of the NFT to approve the spender on.
     * @param _data Data to send along with a safe transfer check.
     * @param deadline A timestamp that specifies the permit's expiration.
     * @param signature A traditional or EIP-2098 signature.
     */
    function safeTransferFromWithPermit(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data,
        uint256 deadline,
        bytes memory signature
    ) external;

    /// @notice Returns the URI of the specified NFT.
    /// @param tokenId The ID of the NFT to get the URI of.
    /// @return The string representation of the NFT's URI.
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

