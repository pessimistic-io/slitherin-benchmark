// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISeaDrop1155 } from "./ISeaDrop1155.sol";

import {     INonFungibleSeaDrop1155Token } from "./INonFungibleSeaDrop1155Token.sol";

import { ISeaDrop1155TokenContractMetadata } from "./ISeaDrop1155TokenContractMetadata.sol";

import {     PublicDrop,     PrivateDrop,     WhiteList,     MultiConfigure,     MintStats,     AirDropParam } from "./SeaDrop1155Structs.sol";

import { SafeTransferLib } from "./SafeTransferLib.sol";

import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import {     IERC165 } from "./IERC165.sol";

import { ECDSA } from "./ECDSA.sol";

import "./ERC1155SeaDrop.sol";

import { Ownable } from "./Ownable.sol";

/**
 * @title  SeaDrop
 * @author James Wenzel (emo.eth)
 * @author Ryan Ghods (ralxz.eth)
 * @author Stephan Min (stephanm.eth)
 * @notice SeaDrop is a contract to help facilitate ERC721 token drops
 *         with functionality for public, allow list, server-side signed,
 *         and token-gated drops.
 */
contract SeaDrop1155 is ISeaDrop1155, ReentrancyGuard, Ownable {
    using ECDSA for bytes32;

    /// @notice Track the public drops.
    mapping(address => PublicDrop) private _publicDrops;

    /// @notice Track the private drop.
    mapping(address => PrivateDrop) private _privateDrops;

    /// @notice Track the air drop.
    mapping(address => WhiteList) private _whiteLists;

    /// @notice Track the creator payout addresses.
    mapping(address => address) private _creatorPayoutAddresses;

    /// @notice Track the private mint prices.
    mapping(address => uint256) private _privateMintPrices;

    /// @notice Track the public mint prices.
    mapping(address => uint256) private _publicMintPrices;

    /// @notice Track the contract name.
    mapping(address => string) private _contractNames;

    /// @notice Track the total minted by stage.
    mapping(address => mapping(uint8 => uint256)) public totalMintedByStage;

    /// @notice Track the wallet minted by stage.
    mapping(address => mapping(uint8 => mapping(address => uint256))) public walletMintedByStage;

    /// @notice Track the stage is active.
    mapping(address => mapping(uint8 => bool)) private _isStageActive;

    /// @notice Track the nftContract signer.
    mapping(address => address) private _signers;
    
    mapping(address => mapping(uint8 => address)) private _feeRecipients;

    mapping(address => mapping(uint8 => uint256)) private _feeValues;

    ERC1155SeaDrop[] private _erc1155SeaDrops;

    /// @notice Constant for an unlimited `maxTokenSupplyForStage`.
    ///         Used in `mintPublic` where no `maxTokenSupplyForStage`
    ///         is stored in the `PublicDrop` struct.
    uint256 internal constant _UNLIMITED_MAX_TOKEN_SUPPLY_FOR_STAGE =
        type(uint256).max;

    /// @notice Constant for a public mint's `dropStageIndex`.
    ///         Used in `mintPublic` where no `dropStageIndex`
    ///         is stored in the `PublicDrop` struct.
    uint8 internal constant _PUBLIC_DROP_STAGE_INDEX = 2;

    /// @notice Constant for a private mint's `dropStageIndex`.
    uint8 internal constant _PRIVATE_DROP_STAGE_INDEX = 1;
    
    /// @notice Constant for a white list mint's `dropStageIndex`.
    uint8 internal constant _WHITE_LIST_STAGE_INDEX = 0;

    /// @notice Constant for a stage mode check stage active.
    uint8 internal constant _START_MODE_CHECK_STAGE_ACTIVE = 1;

    /// @notice Constant for a stage mode not check stage active.
    uint8 internal constant _START_MODE_NOT_CHECK_STAGE_ACTIVE = 0;

    /**
     * @notice Ensure only tokens implementing INonFungibleSeaDropToken can
     *         call the update methods.
     */
    modifier onlyINonFungibleSeaDropToken() virtual {
        if (
            !IERC165(msg.sender).supportsInterface(
                type(INonFungibleSeaDrop1155Token).interfaceId
            )
        ) {
            revert OnlyINonFungibleSeaDropToken(msg.sender);
        }
        _;
    }

    /**
     * @notice Constructor for the contract deployment.
     */
    constructor() {
    }

    /**
     * @notice initialize ERC1155SeaDrop contract.
     * @param _uri the uri for the contract.
     * @param name the name for the contract.
     * @param privateMintPrice the price for private mint.
     * @param publicMintPrice the price for public mint.
     * @param config the config for the contract.
     */
    function initialize(
        string memory _uri,
        string memory name,
        uint256 privateMintPrice,
        uint256 publicMintPrice,
        MultiConfigure calldata config
    ) external override {
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(this);
        // Deploy the ERC1155SeaDrop contract.
        ERC1155SeaDrop erc1155SeaDrop = new ERC1155SeaDrop(_uri, allowedSeaDrop);

        _erc1155SeaDrops.push(erc1155SeaDrop);

        // Configure the ERC1155SeaDrop contract.
        erc1155SeaDrop.multiConfigure(config);

        // Transfer ownership to the deployer.
        erc1155SeaDrop.transferOwnership(msg.sender);

        address erc1155SeaDropAddress = address(erc1155SeaDrop);

        _privateMintPrices[erc1155SeaDropAddress] = privateMintPrice;

        _publicMintPrices[erc1155SeaDropAddress] = publicMintPrice;

        _contractNames[erc1155SeaDropAddress] = name;

        emit ERC1155SeaDropCreated(erc1155SeaDropAddress);
    }

    /**
     * @notice Mint a public drop.
     *
     * @param nftContract      The nft contract to mint.
     * @param nftRecipient     The nft recipient.
     * @param tokenId          The Id of tokens to mint.
     * @param quantity         The number of tokens to mint.
     */
    function mintPublic(
        address nftContract,
        address nftRecipient,
        uint256 tokenId,
        uint256 quantity
    ) external payable override {
        // require(msg.sender == tx.origin, "Not EOA");
        // Get the public drop data.
        PublicDrop memory publicDrop = _publicDrops[nftContract];

        if(publicDrop.startMode == _START_MODE_CHECK_STAGE_ACTIVE) {
            _checkIsStageActive(nftContract, _PUBLIC_DROP_STAGE_INDEX);
            _checkActiveEndTime(publicDrop.endTime);
        } else if (publicDrop.startMode == _START_MODE_NOT_CHECK_STAGE_ACTIVE) {
            // Ensure that the drop has started.
            _checkActive(publicDrop.startTime, publicDrop.endTime);
        } else {
            revert InvalidStartMode(publicDrop.startMode);
        }

        // Put the mint price on the stack.
        uint256 mintPrice = _publicMintPrices[nftContract];

        // Validate payment is correct for number minted.
        _checkCorrectPayment(nftContract, _PUBLIC_DROP_STAGE_INDEX, quantity, mintPrice);

        // Check that the minter is allowed to mint the desired quantity.
        _checkMintQuantity(
            nftContract,
            nftRecipient,
            quantity,
            publicDrop.maxTotalMintableByWallet,
            publicDrop.maxTokenSupplyForStage,
            _PUBLIC_DROP_STAGE_INDEX
        );

        // Mint the token(s), split the payout, emit an event.
        _mintAndPay(
            nftContract,
            nftRecipient,
            tokenId,
            quantity,
            mintPrice,
            _PUBLIC_DROP_STAGE_INDEX
        );
    }

    /**
     * @notice Mint from a private drop.
     *
     * @param nftContract      The nft contract to mint.
     * @param nftRecipient     The nft recipient.
     * @param tokenId         The id of tokens to mint.
     * @param quantity         The number of tokens to mint.
     * @param signature        signed message.

     */
    function mintPrivate(
        address nftContract,
        address nftRecipient,
        uint256 tokenId,
        uint256 quantity,
        bytes memory signature
    ) external payable override {
        // require(msg.sender == tx.origin, "Not EOA");
        //get current stage index whiteListDrop
        PrivateDrop memory privateDrop = _privateDrops[nftContract];

        if(privateDrop.startMode == _START_MODE_CHECK_STAGE_ACTIVE) {
            _checkIsStageActive(nftContract, _PRIVATE_DROP_STAGE_INDEX);
            _checkActiveEndTime(privateDrop.endTime);
        } else if (privateDrop.startMode == _START_MODE_NOT_CHECK_STAGE_ACTIVE) {
            // Check that the drop stage is active.
            _checkActive(privateDrop.startTime, privateDrop.endTime);
        } else {
            revert InvalidStartMode(privateDrop.startMode);
        }

        _checkWhitelistAddress(signature, nftContract, nftRecipient, _PRIVATE_DROP_STAGE_INDEX);

        // Put the mint price on the stack.
        uint256 mintPrice = _privateMintPrices[nftContract];

        // Validate payment is correct for number minted.
        _checkCorrectPayment(nftContract, _PRIVATE_DROP_STAGE_INDEX, quantity, mintPrice);
        
        // Check that the minter is allowed to mint the desired quantity.
        _checkMintQuantity(
            nftContract,
            nftRecipient,
            quantity,
            privateDrop.maxTotalMintableByWallet,
            privateDrop.maxTokenSupplyForStage,
            _PRIVATE_DROP_STAGE_INDEX
        );

        // Mint the token(s), split the payout, emit an event.
        _mintAndPay(
            nftContract,
            nftRecipient,
            tokenId,
            quantity,
            mintPrice,
            _PRIVATE_DROP_STAGE_INDEX
        );
    }

     /**
     * @notice Mint from an white list.
     *
     * @param nftContract      The nft contract to mint.
     * @param nftRecipient     The nft recipient.
     * @param tokenId          The id of tokens to mint.
     * @param quantity         The number of tokens to mint.
     * @param signature        signed message.

     */
    function whiteListMint(
        address nftContract,
        address nftRecipient,
        uint256 tokenId,
        uint256 quantity,
        bytes memory signature
    ) external payable override {
        // require(msg.sender == tx.origin, "Not EOA");
        //get current stage whiteList
        WhiteList memory whiteList = _whiteLists[nftContract];

        if(whiteList.startMode == _START_MODE_CHECK_STAGE_ACTIVE) {
            _checkIsStageActive(nftContract, _WHITE_LIST_STAGE_INDEX);
            _checkActiveEndTime(whiteList.endTime);
        } else if (whiteList.startMode == _START_MODE_NOT_CHECK_STAGE_ACTIVE) {
            // Check that the drop stage is active.
            _checkActive(whiteList.startTime, whiteList.endTime);
        } else {
            revert InvalidStartMode(whiteList.startMode);
        }

        _checkWhitelistAddress(signature, nftContract, nftRecipient, _WHITE_LIST_STAGE_INDEX);

        // Validate payment is correct for number minted.
        _checkCorrectPayment(nftContract, _WHITE_LIST_STAGE_INDEX, quantity, 0);

        // Check that the minter is allowed to mint the desired quantity.
        _checkMintQuantity(
            nftContract,
            nftRecipient,
            quantity,
            whiteList.maxTotalMintableByWallet,
            whiteList.maxTokenSupplyForStage,
            _WHITE_LIST_STAGE_INDEX
        );

        // Mint the token(s), split the payout, emit an event.
        _mintAndPay(
            nftContract,
            nftRecipient,
            tokenId,
            quantity,
            0,
            _WHITE_LIST_STAGE_INDEX
        );
    }

    /**
     * @notice airdrop.
     *
     * @param nftContract      The nft contract to mint.
     * @param airDropParams      airdrop params.
     */
    function airdrop(
        address nftContract,
        AirDropParam[] calldata airDropParams
    ) external override {
        // require(msg.sender == tx.origin, "Not EOA");

        require(ERC1155SeaDrop(nftContract).owner() == msg.sender, "Not nft owner");
        
        for (uint256 i; i < airDropParams.length; ) {
            AirDropParam memory airDropParam = airDropParams[i];
            // Get the mint stats.
            MintStats memory mintStats = INonFungibleSeaDrop1155Token(nftContract).getMintStats();

            if (airDropParam.quantity + mintStats.totalMinted > mintStats.maxSupply) {
                revert MintQuantityExceedsMaxSupply(
                    airDropParam.quantity + mintStats.totalMinted ,
                    mintStats.maxSupply
                );
            }

            _mintAirDrop(
                nftContract,
                airDropParam.nftRecipient,
                airDropParam.tokenId,
                airDropParam.quantity
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Check that the drop stage is active.
     *
     * @param startTime The drop stage start time.
     * @param endTime   The drop stage end time.
     */
    function _checkActive(uint256 startTime, uint256 endTime) internal view {
        if (
            _cast(block.timestamp < startTime) |
                _cast(block.timestamp > endTime) ==
            1
        ) {
            // Revert if the drop stage is not active.
            revert NotActive(block.timestamp, startTime, endTime);
        }
    }

    /**
     * @notice Check that the drop stage is active.
     *
     * @param endTime   The drop stage end time.
     */
    function _checkActiveEndTime(uint256 endTime) internal view {
        if (
            
            _cast(block.timestamp > endTime) == 1
        ) {
            // Revert if the drop stage is not active.
            revert NotActiveEndTime(block.timestamp, endTime);
        }
    }

    /**
     * @notice Check that the wallet is allowed to mint the desired quantity.
     *
     * @param nftContract              The nft contract.
     * @param nftRecipient             The nft recipient.
     * @param quantity                 The number of tokens to mint.
     * @param maxTotalMintableByWallet The max allowed mints per wallet.
     * @param maxTokenSupplyForStage   The max token supply for the drop stage.
     * @param stageIndex               The stage index.
     */
    function _checkMintQuantity(
        address nftContract,
        address nftRecipient,
        uint256 quantity,
        uint256 maxTotalMintableByWallet,
        uint256 maxTokenSupplyForStage,
        uint8 stageIndex
    ) internal view {
        // Mint quantity of zero is not valid.
        if (quantity == 0) {
            revert MintQuantityCannotBeZero();
        }
        // Get the mint stats.
        MintStats memory mintStats = INonFungibleSeaDrop1155Token(nftContract).getMintStats();
        uint256 totalSupply = mintStats.totalMinted;
        uint256 maxSupply = mintStats.maxSupply;

        uint256 minterNumMinted = walletMintedByStage[nftContract][stageIndex][nftRecipient];
        uint256 currentTotalSupply = totalMintedByStage[nftContract][stageIndex];

        // Ensure mint quantity doesn't exceed maxTotalMintableByWallet.
        if (quantity + minterNumMinted > maxTotalMintableByWallet) {
            revert MintQuantityExceedsMaxMintedPerWallet(
                quantity + minterNumMinted,
                maxTotalMintableByWallet
            );
        }

        // Ensure mint quantity doesn't exceed maxSupply.
        if (quantity + totalSupply > maxSupply) {
            revert MintQuantityExceedsMaxSupply(
                quantity + totalSupply,
                maxSupply
            );
        }

        // Ensure mint quantity doesn't exceed maxTokenSupplyForStage.
        if (quantity + currentTotalSupply > maxTokenSupplyForStage) {
            revert MintQuantityExceedsMaxTokenSupplyForStage(
                quantity + currentTotalSupply,
                maxTokenSupplyForStage
            );
        }
    }

    /**
     * @notice Revert if the payment is not the quantity times the mint price plus fee value.
     *
     * @param nftContract  The nft contract address.
     * @param stageIndex  The stage index.
     * @param quantity  The number of tokens to mint.
     * @param mintPrice The mint price per token.
     */
    function _checkCorrectPayment(address nftContract, uint8 stageIndex, uint256 quantity, uint256 mintPrice)
        internal
        view
    {
        // Get the fee value.
        uint256 feeValue = _feeValues[nftContract][stageIndex];
        // Revert if the tx's value doesn't match the total cost.
        if (msg.value != quantity * mintPrice + feeValue) {
            revert IncorrectPayment(msg.value, quantity * mintPrice + feeValue);
        }
    }

    /**
     * @notice Split the payment payout for the creator and fee recipient.
     *
     * @param nftContract  The nft contract.
     */
    function _splitPayout(
        address nftContract,
        uint8 stageIndex
    ) internal {
        // Get the creator payout address.
        address creatorPayoutAddress = _creatorPayoutAddresses[nftContract];

        // Ensure the creator payout address is not the zero address.
        if (creatorPayoutAddress == address(0)) {
            revert CreatorPayoutAddressCannotBeZeroAddress();
        }

        // Get the fee amount.
        uint256 feeValue = _feeValues[nftContract][stageIndex];

        address feeRecipient = _feeRecipients[nftContract][stageIndex];
        
        // Get the creator payout amount. Fee amount is <= msg.value per above.
        uint256 payoutAmount;
        unchecked {
            payoutAmount = msg.value - feeValue;
        }
        
        // Transfer the fee amount to the fee recipient.
        if (feeValue > 0) {
            if (feeRecipient == address(0)) {
                SafeTransferLib.safeTransferETH(owner(), feeValue);
            } else {
                SafeTransferLib.safeTransferETH(feeRecipient, feeValue);
            }
        }
        if (payoutAmount > 0) {
            // Transfer the creator payout amount to the creator.
            SafeTransferLib.safeTransferETH(creatorPayoutAddress, payoutAmount);
        }
    }

    /**
     * @notice Mints a number of tokens, splits the payment,
     *         and emits an event.
     *
     * @param nftContract    The nft contract.
     * @param nftRecipient   The nft recipient.
     * @param tokenId        The id of tokens to mint.
     * @param quantity       The number of tokens to mint.
     * @param mintPrice      The mint price per token.
     * @param stageIndex     The stage index.
     */
    function _mintAndPay(
        address nftContract,
        address nftRecipient,
        uint256 tokenId,
        uint256 quantity,
        uint256 mintPrice,
        uint8 stageIndex
    ) internal nonReentrant {
        // Mint the token(s).
        INonFungibleSeaDrop1155Token(nftContract).mintSeaDrop(nftRecipient, tokenId, quantity);

        totalMintedByStage[nftContract][stageIndex] += quantity;
        walletMintedByStage[nftContract][stageIndex][nftRecipient] += quantity;

        // Split the payment between the creator and fee recipient.
        _splitPayout(nftContract, stageIndex);

        // Emit an event for the mint.
        emit SeaDropMint(
            nftContract,
            nftRecipient,
            msg.sender,
            tokenId,
            quantity,
            mintPrice
        );
    }

     /**
     * @notice Mints a number of tokens,
     *         and emits an event.
     *
     * @param nftContract    The nft contract.
     * @param nftRecipient   The nft recipient.
     * @param quantity       The number of tokens to mint.
     */
    function _mintAirDrop(
        address nftContract,
        address nftRecipient,
        uint256 tokenId,
        uint256 quantity
    ) internal nonReentrant {
        // Mint the token(s).
        INonFungibleSeaDrop1155Token(nftContract).mintSeaDrop(nftRecipient, tokenId, quantity);

        // Emit an event for the mint.
        emit SeaDropMint(
            nftContract,
            nftRecipient,
            msg.sender,
            tokenId,
            quantity,
            0
        );
    }

    /**
     * @notice Returns the public drop data for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getPublicDrop(address nftContract)
        external
        view
        override
        returns (PublicDrop memory, uint256, uint256)
    {
        return (_publicDrops[nftContract], _publicMintPrices[nftContract], totalMintedByStage[nftContract][_PUBLIC_DROP_STAGE_INDEX]);
    }

    /**
     * @notice Returns the white list data for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getWhiteList(address nftContract)
        external
        view
        override
        returns (WhiteList memory, uint256)
    {
        return (_whiteLists[nftContract], totalMintedByStage[nftContract][_WHITE_LIST_STAGE_INDEX]);
    }

    /**
     * @notice Returns the creator payout address for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getCreatorPayoutAddress(address nftContract)
        external
        view
        override
        returns (address)
    {
        return _creatorPayoutAddresses[nftContract];
    }


    /**
     * @notice Returns the private drops for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getPrivateDrop(address nftContract)
        external
        view
        override
        returns (PrivateDrop memory, uint256, uint256)
    {
        return (_privateDrops[nftContract], _privateMintPrices[nftContract], totalMintedByStage[nftContract][_PRIVATE_DROP_STAGE_INDEX]);
    }

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
    function updatePublicDrop(PublicDrop calldata publicDrop)
        external
        override
        onlyINonFungibleSeaDropToken
    {
        // Set the public drop data.
        _publicDrops[msg.sender] = publicDrop;

        // Emit an event with the update.
        emit PublicDropUpdated(msg.sender, publicDrop);
    }

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
     * @param privateDrop The white list drop.
     */
    function updatePrivateDrop(PrivateDrop calldata privateDrop)
        external
        override
        onlyINonFungibleSeaDropToken
    {
        
        _privateDrops[msg.sender] = privateDrop;

        // Emit an event with the update.
        emit PrivateDropUpdated(
            msg.sender,
            privateDrop
        );
    }

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
     * @param whiteList The white list.
     */
    function updateWhiteList(WhiteList calldata whiteList)
        external
        override
        onlyINonFungibleSeaDropToken
    {
        
        _whiteLists[msg.sender] = whiteList;

        // Emit an event with the update.
        emit WhiteListUpdated(
            msg.sender,
            whiteList
        );
    }

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
    function updateCreatorPayoutAddress(address payoutAddress)
        external
        override
        onlyINonFungibleSeaDropToken
    {
        if (payoutAddress == address(0)) {
            revert CreatorPayoutAddressCannotBeZeroAddress();
        }
        // Set the creator payout address.
        _creatorPayoutAddresses[msg.sender] = payoutAddress;

        // Emit an event with the update.
        emit CreatorPayoutAddressUpdated(msg.sender, payoutAddress);
    }

    /**
     * @notice Updates the signer address and emits an event.
     *
     *         This method assume msg.sender is an nft contract and its
     *         ERC165 interface id matches INonFungibleSeaDropToken.
     *
     *         Note: Be sure only authorized users can call this from
     *         token contracts that implement INonFungibleSeaDropToken.
     *
     * @param signer The signer address.
     */
    function updateSigner(address signer) 
        external
        override
        onlyINonFungibleSeaDropToken
    {
        if (signer == address(0)) {
            revert SignerAddressCannotBeZeroAddress();
        }
        // Set the creator payout address.
        _signers[msg.sender] = signer;

        // Emit an event with the update.
        emit SignerUpdated(msg.sender, signer);
    }

    /**
     * @notice Update fee recipient address and fee value and emits an event.
     *
     * @param nftContract The nft contract.
     * @param stageIndex stage index.
     * @param feeRecipient The fee recipient address.
     * @param feeValue The fee value.
     */
    function updateFee(
        address nftContract,
        uint8 stageIndex,
        address feeRecipient,
        uint256 feeValue
    ) external override onlyOwner {
        if (feeRecipient == address(0)) {
            revert FeeRecipientAddressCannotBeZeroAddress();
        }
        if (feeValue == 0) {
            revert FeeValueCannotBeZero();
        }
        // Set the fee recipient.
        _feeRecipients[nftContract][stageIndex] = feeRecipient;

        // Set the fee value.
        _feeValues[nftContract][stageIndex] = feeValue;

        // Emit an event with the update.
        emit FeeUpdated(nftContract, stageIndex, feeRecipient, feeValue);
    }

    /**
     * @dev Internal pure function to cast a `bool` value to a `uint256` value.
     *
     * @param b The `bool` value to cast.
     *
     * @return u The `uint256` value.
     */
    function _cast(bool b) internal pure returns (uint256 u) {
        assembly {
            u := b
        }
    }

    function _hashTransaction(address seadrop, address token, address nftRecipient, uint8 stage) internal pure returns (bytes32) {
         bytes32 hash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            keccak256(abi.encodePacked(seadrop, token, nftRecipient, stage))
        ));
         return hash;
    }

    /**
     * @dev checks if the signature is valid for the given parameters
     *
     * @param signature The signature to check.
     * @param token The token address.
     * @param nftRecipient The nft recipient address.
     * @param stage The stage.
     */
    function _checkWhitelistAddress(bytes memory signature, address token, address nftRecipient, uint8 stage) internal view {
        bytes32 msgHash = _hashTransaction(address(this), token, nftRecipient, stage);
        if (msgHash.recover(signature) != _signers[token]) {
            revert MinterNotWhitelist(address(this), token, nftRecipient, stage);
        }
    }

    function _checkIsStageActive(address nftContract, uint8 stage) internal view {
        if (_isStageActive[nftContract][stage] == false) {
            revert StageNotActive(nftContract, stage);
        }
    }

    /**
     * @notice Returns the private mint price for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getPrivateMintPrice(address nftContract)
        external
        view
        override
        returns (uint256)
    {
        return _privateMintPrices[nftContract];
    }

    /**
     * @notice Returns the public mint price for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getPublicMintPrice(address nftContract)
        external
        view
        override
        returns (uint256)
    {
        return _publicMintPrices[nftContract];
    }

    /**
     * @notice Returns the contract name for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getContractName(address nftContract)
        external
        view
        override
        returns (string memory)
    {
        return _contractNames[nftContract];
    }

    /**
     * @notice Returns the signer address for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getSigner(address nftContract)
        external
        view
        override
        returns (address)
    {
        return _signers[nftContract];
    }

    /**
     * @notice Returns the fee recipient and fee value for the nft contract.
     *
     */
    function getFee(address nftContract, uint8 stageIndex)
        external
        view
        override
        returns (address, uint256)
    {
        return (_feeRecipients[nftContract][stageIndex],_feeValues[nftContract][stageIndex]);
    }

    /**
     * @notice Withdraw eth.
     *
     * @param recipient The eth recipient.
     */
    function withdrawETH(address recipient)
        external 
        onlyOwner
        override
        returns (uint256 balance)
    {
        balance = address(this).balance;
        if (balance > 0) SafeTransferLib.safeTransferETH(recipient, balance);

        emit WithdrawnETH(recipient, balance);
    }

    /**
     * @notice Returns the mint stats for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getMintStats(address nftContract) 
        external 
        view 
        override
        returns (MintStats memory) 
    {
        return INonFungibleSeaDrop1155Token(nftContract).getMintStats();
    }

    /**
     * @notice Returns the stage is active for the nft contract.
     *
     * @param nftContract The nft contract.
     * @param stage The stage.
     */
    function getIsStageActive(address nftContract, uint8 stage) external view override returns (bool) {
        return _isStageActive[nftContract][stage];
    }

    /**
     * @notice Update mint stage active.
     *
     * @param nftContract The nft contract.
     * @param stage The stage.
     * @param isActive The stage is active.
     */
    function updateMint(
        address nftContract,
        uint8 stage,
        bool isActive
    ) external override {
        // require(msg.sender == tx.origin, "Not EOA");

        require(ERC1155SeaDrop(nftContract).owner() == msg.sender, "Not nft owner");

        if (stage == _WHITE_LIST_STAGE_INDEX || 
            stage == _PRIVATE_DROP_STAGE_INDEX || 
            stage == _PUBLIC_DROP_STAGE_INDEX
        ) {
            _updateIsStageActive(nftContract, stage, isActive);
        } else {
            revert InvalidStage(stage);
        }

        emit MintUpdated(nftContract, stage, isActive);
    }

    /**
     * @dev Update mint stage active.
     *
     * @param nftContract The nft contract.
     * @param stage The stage.
     * @param isActive The stage is active.
     */
    function _updateIsStageActive(address nftContract, uint8 stage, bool isActive) internal  {
        require(ERC1155SeaDrop(nftContract).owner() == msg.sender, "Not nft owner");

        _isStageActive[nftContract][stage] = isActive;

        emit StageActiveUpdated(nftContract, stage, isActive);
    }

    function allERC1155SeaDrops() external view returns (ERC1155SeaDrop[] memory) {
        return _erc1155SeaDrops;
    }
}

