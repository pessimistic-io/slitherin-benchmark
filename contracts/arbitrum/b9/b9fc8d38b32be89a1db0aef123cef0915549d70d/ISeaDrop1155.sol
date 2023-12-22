// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {     PublicDrop,     PrivateDrop,     WhiteList,     MultiConfigure,     MintStats,     AirDropParam } from "./SeaDrop1155Structs.sol";

import { SeaDrop1155ErrorsAndEvents } from "./SeaDrop1155ErrorsAndEvents.sol";

interface ISeaDrop1155 is SeaDrop1155ErrorsAndEvents {

    /**
     * @notice Initialize the nft contract
     *
     * @param _uri      Parameters required to construct ERC1155.
     * @param name     nft contract name.
     * @param privateMintPrice     The nft contract private drop price.
     * @param publicMintPrice     The nft contract public drop price.
     * @param config     The nft contract batch config struct.
     */
    function initialize(
        string memory _uri,
        string memory name,
        uint256 privateMintPrice,
        uint256 publicMintPrice,
        MultiConfigure calldata config
    ) external;

    /**
     * @notice Mint a public drop.
     *
     * @param nftContract      The nft contract to mint.
     * @param nftRecipient      The nft recipient.
     * @param tokenId         The Id of tokens to mint.
     * @param quantity         The number of tokens to mint.
     */
    function mintPublic(
        address nftContract,
        address nftRecipient,
        uint256 tokenId,
        uint256 quantity
    ) external payable;

    /**
     * @notice Mint a private drop.
     *
     * @param nftContract      The nft contract to mint.
     * @param nftRecipient      The nft recipient.
     * @param tokenId          The Id of tokens to mint.
     * @param quantity         The number of tokens to mint.
     * @param signature        signed message.
     */
    function mintPrivate(
        address nftContract,
        address nftRecipient,
        uint256 tokenId,
        uint256 quantity,
        bytes memory signature
    ) external payable;

    /**
     * @notice Mint a air drop.
     *
     * @param nftContract      The nft contract to mint.
     * @param nftRecipient      The nft recipient.
     * @param tokenId          The Id of tokens to mint.
     * @param quantity         The number of tokens to mint.
     * @param signature        signed message.
     */
    function whiteListMint(
        address nftContract,
        address nftRecipient,
        uint256 tokenId,
        uint256 quantity,
        bytes memory signature
    ) external payable;

    /**
     * @notice airdrop.
     *
     * @param nftContract      The nft contract to mint.
     * @param AirDropParams      params.
     */
    function airdrop(
        address nftContract,
        AirDropParam[] calldata AirDropParams
    ) external;
    /**
     * @notice Updates the public drop data for the nft contract
     *         and emits an event.
     *
     *         This method assume msg.sender is an nft contract and its
     *         ERC165 interface id matches INonFungibleSeaDropToken.
     *
     *         Note: Be sure only authorized users can call this from
     *         token contracts that implement INonFungibleSeaDropToken.
     *
     * @param publicDrop The public drop data.
     */
    function updatePublicDrop(PublicDrop calldata publicDrop) external;

    /**
     * @notice Updates the private drop data for the nft contract
     *         and emits an event.
     *
     *         This method assume msg.sender is an nft contract and its
     *         ERC165 interface id matches INonFungibleSeaDropToken.
     *
     *         Note: Be sure only authorized users can call this from
     *         token contracts that implement INonFungibleSeaDropToken.
     *
     * @param privateDrop The private drop.
     */
    function updatePrivateDrop(PrivateDrop calldata privateDrop) external;

    /**
     * @notice Updates the white list data for the nft contract
     *         and emits an event.
     *
     *         This method assume msg.sender is an nft contract and its
     *         ERC165 interface id matches INonFungibleSeaDropToken.
     *
     *         Note: Be sure only authorized users can call this from
     *         token contracts that implement INonFungibleSeaDropToken.
     *
     * @param whiteList The air drop.
     */
    function updateWhiteList(WhiteList calldata whiteList) external;

    /**
     * @notice Updates the creator payout address and emits an event.
     *
     *         This method assume msg.sender is an nft contract and its
     *         ERC165 interface id matches INonFungibleSeaDropToken.
     *
     *         Note: Be sure only authorized users can call this from
     *         token contracts that implement INonFungibleSeaDropToken.
     *
     * @param payoutAddress The creator payout address.
     */
    function updateCreatorPayoutAddress(address payoutAddress) external;

    /**
     * @notice Updates the signer address for the nft contract.
     *
     * @param signer The nft signer address.
     */
    function updateSigner(address signer) external;

    function updateFee(
        address nftContract,
        uint8 stage,
        address FeeRecipient,
        uint256 FeeValue
    ) external;

    /**
     * @notice Returns the public drop data for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getPublicDrop(address nftContract)
        external
        view
        returns (PublicDrop memory, uint256, uint256);

    /**
     * @notice Returns the white list data for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getWhiteList(address nftContract)
        external
        view
        returns (WhiteList memory, uint256);

    /**
     * @notice Returns the creator payout address for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getCreatorPayoutAddress(address nftContract)
        external
        view
        returns (address);

    /**
     * @notice Returns the private drop for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getPrivateDrop(address nftContract)
        external
        view
        returns (PrivateDrop memory, uint256, uint256);
    
    /**
     * @notice Returns the private mint price for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getPrivateMintPrice(address nftContract)
        external
        view
        returns (uint256);

    /**
     * @notice Returns the public mint price for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getPublicMintPrice(address nftContract)
        external
        view
        returns (uint256);

    /**
     * @notice Returns the contract name for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getContractName(address nftContract)
        external
        view
        returns (string memory);

    /**
     * @notice Returns the signer address for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getSigner(address nftContract)
        external
        view
        returns (address);

    function getFee(address nftContract, uint8 stageIndex) external view returns (address, uint256);

    /**
     * @notice Returns the mint stats data for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getMintStats(address nftContract) external view returns (MintStats memory);

    /**
     * @notice Withdraw ETH for the nft contract.
     *
     * @param recipient Address to receive nft.
     */
    function withdrawETH(address recipient) external returns (uint256 balance);

    /**
     * @notice Returns the is stage active for the nft contract.
     *
     * @param nftContract The nft contract.
     * @param stage       stage index.
     */
    function getIsStageActive(address nftContract, uint8 stage) external view returns (bool);

    /**
     * @notice Update mint stage active for the nft contract.
     *
     * @param nftContract The nft contract.
     * @param stage       stage index.
     * @param isActive       stage is active.
     */
    function updateMint(
        address nftContract,
        uint8 stage,
        bool isActive
    ) external;
}

