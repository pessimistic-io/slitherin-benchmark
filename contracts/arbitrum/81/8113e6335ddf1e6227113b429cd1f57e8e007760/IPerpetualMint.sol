// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { IOwnable } from "./IOwnable.sol";
import { IERC165Base } from "./IERC165Base.sol";
import { IPausable } from "./IPausable.sol";
import { IERC1155Base } from "./IERC1155Base.sol";
import { IERC1155Metadata } from "./IERC1155Metadata.sol";

import { IERC1155MetadataExtension } from "./IERC1155MetadataExtension.sol";
import { IPerpetualMintInternal } from "./IPerpetualMintInternal.sol";
import { PerpetualMintStorage as Storage, TiersData, VRFConfig } from "./Storage.sol";

/// @title IPerpetualMint
/// @dev Interface of the PerpetualMint facet
interface IPerpetualMint is
    IERC1155Base,
    IERC1155Metadata,
    IERC165Base,
    IOwnable,
    IPerpetualMintInternal,
    IPausable,
    IERC1155MetadataExtension
{
    /// @notice Attempts a batch mint for the msg.sender for a single collection using ETH as payment.
    /// @param collection address of collection for mint attempts
    /// @param numberOfMints number of mints to attempt
    function attemptBatchMintWithEth(
        address collection,
        uint32 numberOfMints
    ) external payable;

    /// @notice Attempts a batch mint for the msg.sender for a single collection using $MINT tokens as payment.
    /// @param collection address of collection for mint attempts
    /// @param numberOfMints number of mints to attempt
    function attemptBatchMintWithMint(
        address collection,
        uint32 numberOfMints
    ) external;

    /// @notice burns a receipt after a claim request is fulfilled
    /// @param tokenId id of receipt to burn
    function burnReceipt(uint256 tokenId) external;

    /// @notice Cancels a claim for a given claimer for given token ID
    /// @param claimer address of rejected claimer
    /// @param tokenId token ID of rejected claim
    function cancelClaim(address claimer, uint256 tokenId) external;

    /// @notice claims all accrued mint earnings across collections
    function claimMintEarnings() external;

    /// @notice Initiates a claim for a prize for a given collection
    /// @param prizeRecipient address of intended prize recipient
    /// @param tokenId token ID of prize, which is the prize collection address encoded as uint256
    function claimPrize(address prizeRecipient, uint256 tokenId) external;

    /// @notice claims all accrued protocol fees
    function claimProtocolFees() external;

    /// @notice mints an amount of mintToken tokens to the mintToken contract in exchange for ETH
    /// @param amount amount of mintToken tokens to mint
    function mintAirdrop(uint256 amount) external payable;

    /// @notice Validates receipt of an ERC1155 transfer.
    /// @param operator Executor of transfer.
    /// @param from Sender of tokens.
    /// @param id Token ID received.
    /// @param value Quantity of tokens received.
    /// @param data Data payload.
    /// @return bytes4 Function's own selector if transfer is accepted.
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external pure returns (bytes4);

    /// @notice Triggers paused state, when contract is unpaused.
    function pause() external;

    /// @notice redeems an amount of $MINT tokens for ETH (native token) for the msg.sender
    /// @param amount amount of $MINT
    function redeem(uint256 amount) external;

    /// @notice set the mint price for a given collection
    /// @param collection address of collection
    /// @param price mint price of the collection
    function setCollectionMintPrice(address collection, uint256 price) external;

    /// @notice sets the risk of a given collection
    /// @param collection address of collection
    /// @param risk new risk value for collection
    function setCollectionRisk(address collection, uint32 risk) external;

    /// @notice sets the consolation fee in basis points
    /// @param consolationFeeBP consolation fee in basis points
    function setConsolationFeeBP(uint32 consolationFeeBP) external;

    /// @notice sets the ratio of ETH (native token) to $MINT for mint attempts using $MINT as payment
    /// @param ratio ratio of ETH to $MINT
    function setEthToMintRatio(uint256 ratio) external;

    /// @notice sets the mint fee in basis points
    /// @param mintFeeBP mint fee in basis points
    function setMintFeeBP(uint32 mintFeeBP) external;

    /// @notice sets the address of the mint consolation token
    /// @param mintToken address of the mint consolation token
    function setMintToken(address mintToken) external;

    /// @notice sets the baseURI for the ERC1155 token receipts
    /// @param baseURI URI string
    function setReceiptBaseURI(string calldata baseURI) external;

    /// @notice sets the tokenURI for ERC1155 token receipts
    /// @param tokenId token ID, which is the collection address encoded as uint256
    /// @param tokenURI URI string
    function setReceiptTokenURI(
        uint256 tokenId,
        string calldata tokenURI
    ) external;

    /// @notice sets the redemption fee in basis points
    /// @param _redemptionFeeBP redemption fee in basis points
    function setRedemptionFeeBP(uint32 _redemptionFeeBP) external;

    /// @notice sets the $MINT consolation tiers
    /// @param tiersData TiersData struct holding all related data to $MINT consolation tiers
    function setTiers(TiersData calldata tiersData) external;

    /// @notice sets the Chainlink VRF config
    /// @param config VRFConfig struct holding all related data to ChainlinkVRF setup
    function setVRFConfig(VRFConfig calldata config) external;

    /// @notice sets the minimum threshold for the VRF subscription balance in LINK tokens
    /// @param vrfSubscriptionBalanceThreshold minimum threshold for the VRF subscription balance in LINK tokens
    function setVRFSubscriptionBalanceThreshold(
        uint96 vrfSubscriptionBalanceThreshold
    ) external;

    ///  @notice Triggers unpaused state, when contract is paused.
    function unpause() external;
}

