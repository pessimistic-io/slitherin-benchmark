// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Simplr
pragma solidity 0.8.11;

import "./PaymentSplitableA.sol";
import "./ICollectionStruct.sol";
import "./MerkleProofUpgradeable.sol";

/// @title PresaleableA
/// @author Chain Labs
/// @notice Module that adds functionality of presale with an optional whitelist presale.
/// @dev Uses merkle proofs for whitelist
contract PresaleableA is PaymentSplitableA, ICollectionStruct {
    //------------------------------------------------------//
    //
    //  Storage
    //
    //------------------------------------------------------//
    /// @notice merkle root of tree generated from whitelisted addresses
    /// @dev list is stored on IPFS and CID is stored in the state
    /// @return merkleRoot merkle root
    bytes32 public merkleRoot;

    /// @notice CID of file containing list of whitelisted addresses
    /// @dev IPFS CID of JSON file with list of addresses
    /// @return whitelistCid IPFS CID
    string public whitelistCid;

    /// @notice tokens to be sold in presale
    /// @dev maximum tokens to be sold in presale, if not sold, will be rolled over to public sale
    /// @return presaleReservedTokens tokens to be sold in presale
    uint256 public presaleReservedTokens; // number of tokens reserved for presale

    /// @notice maximum tokens an account can buy/mint during presale
    /// @dev maximum tokens an account can buy/mint during presale
    /// @return presaleMaxHolding maximum tokens an account can hold during presale
    uint256 public presaleMaxHolding; // number of tokens a collector can hold during presale

    /// @notice price per token during presale
    /// @dev price per token during presale
    /// @return presalePrice price per token during presale
    uint256 public presalePrice; // price of token during presale

    /// @notice timestamp when presale starts
    /// @dev presale starts automatically at this time and ends when public sale starts
    /// @return presaleStartTime timestamp when presale starts
    uint256 public presaleStartTime; // presale start timestamp

    //------------------------------------------------------//
    //
    //  Events
    //
    //------------------------------------------------------//

    event PresaleSetup(
        uint256 presaleReservedTokens,
        uint256 presalePrice,
        uint256 presaleStartTime,
        uint256 presaleMaxHolding,
        bytes32 indexed whitelistRoot,
        string whitelistCid
    );

    event PublicSaleStartTimeUpdated(uint256 newSaleStartTime);

    event PresaleStartTimeUpdated(uint256 newPresaleStartTime);

    /// @notice logs updated whitelist details
    /// @dev emitted when whitelist updated, logs new merkle root and IPFS CID
    /// @param whitelistRoot updated merkle root generated from new list of whitelisted addresses
    /// @param whitelistCid IPFS CID containing updated list of whitelist addresses
    event WhitelistUpdated(bytes32 indexed whitelistRoot, string whitelistCid);

    event PresalePriceUpdated(uint256 presalePrice);

    event PresaleMaxHoldingUpdated(uint256 presaleMaxHolding);

    event MaximumTokensUpdated(uint256 maximumTokens);

    event PresaleReservedTokensUpdated(uint256 presaleReservedTokens);

    //------------------------------------------------------//
    //
    //  Modifiers
    //
    //------------------------------------------------------//

    modifier presaleAllowed() {
        require(isPresaleAllowed(), "PR:001");
        _;
    }

    //------------------------------------------------------//
    //
    //  Setup
    //
    //------------------------------------------------------//

    /// @notice setup presale details including whitelist
    /// @dev internal method and can only be invoked when Collection is being setup
    /// @param _presaleReservedTokens maximum number of tokens to be sold in presale
    /// @param _presalePrice price per token during presale
    /// @param _presaleStartTime timestamp when presale starts
    /// @param _presaleMaxHolding maximum tokens and account can hold during presale
    /// @param _presaleWhitelist struct containing whitelist details
    function setupPresale(
        uint256 _presaleReservedTokens,
        uint256 _presalePrice,
        uint256 _presaleStartTime,
        uint256 _presaleMaxHolding,
        Whitelist memory _presaleWhitelist
    ) internal {
        if (_presaleStartTime != 0) {
            require(_presaleReservedTokens != 0, "PR:002");
            require(_presaleStartTime > block.timestamp, "PR:003");
            require(_presaleMaxHolding != 0, "PR:004");
            presaleReservedTokens = _presaleReservedTokens;
            presalePrice = _presalePrice;
            presaleStartTime = _presaleStartTime;
            presaleMaxHolding = _presaleMaxHolding;
            if (!(_presaleWhitelist.root == bytes32(0))) {
                _setWhitelist(_presaleWhitelist);
            }
        }
    }

    //------------------------------------------------------//
    //
    //  Owner only functions
    //
    //------------------------------------------------------//

    /// @notice set new sale start time for presale and public sale
    /// @dev single method to set timestamp for public sale and presale
    /// @param _newSaleStartTime new timestamp
    /// @param saleType sale type, true - set for public sale, when saleType is false - set for presale
    function setSaleStartTime(uint256 _newSaleStartTime, bool saleType)
        external
        onlyOwner
    {
        if (saleType) {
            require(
                _newSaleStartTime > block.timestamp &&
                    _newSaleStartTime != publicSaleStartTime &&
                    _newSaleStartTime > presaleStartTime,
                "BC:006"
            );
            publicSaleStartTime = _newSaleStartTime;
        } else {
            require(
                _newSaleStartTime > block.timestamp &&
                    _newSaleStartTime != presaleStartTime &&
                    _newSaleStartTime < publicSaleStartTime,
                "PR:008"
            );
            presaleStartTime = _newSaleStartTime;
            emit PresaleStartTimeUpdated(_newSaleStartTime);
        }
    }

    /// @notice update whitelist
    /// @dev update whitelist merkle root and IPFS CID
    /// @param _whitelist struct containing new whitelist details
    function updateWhitelist(Whitelist memory _whitelist)
        external
        onlyOwner
        presaleAllowed
    {
        _setWhitelist(_whitelist);
    }

    /// @notice sets new price for presale
    /// @dev only owner can change presale price
    /// @param _newPresalePrice new presale price
    function setPresalePrice(uint256 _newPresalePrice) external onlyOwner {
        presalePrice = _newPresalePrice;
        emit PresalePriceUpdated(_newPresalePrice);
    }

    /// @notice Change number of tokens that be minted by an account in presale
    /// @dev only owner can update maximum holding limit per account in presale
    /// @param _newPresaleMaxHolding new maximum holding limit in presale
    function setPresaleMaxHolding(uint256 _newPresaleMaxHolding)
        external
        onlyOwner
    {
        presaleMaxHolding = _newPresaleMaxHolding;
        emit PresaleMaxHoldingUpdated(_newPresaleMaxHolding);
    }

    /// @notice Change maximum tokens
    /// @dev only owner can update maximum tokens
    /// @param _newMaximumTokens new maximum tokens
    function setMaximumTokens(uint256 _newMaximumTokens) external onlyOwner {
        require(
            _newMaximumTokens >= totalSupply() &&
                _newMaximumTokens >= presaleReservedTokens + reservedTokens,
            "BC:015"
        );
        maximumTokens = _newMaximumTokens;
        emit MaximumTokensUpdated(_newMaximumTokens);
    }

    /// @notice change presale reserved tokens
    /// @dev only owner can change presale reserved tokens
    /// @param _newPresaleReservedTokens new presale reserved tokens
    function setPresaleReservedTokens(uint256 _newPresaleReservedTokens)
        external
        onlyOwner
    {
        require(
            _newPresaleReservedTokens + reservedTokens <= maximumTokens &&
                _newPresaleReservedTokens + reservedTokens >= totalSupply(),
            "PR:015"
        );
        presaleReservedTokens = _newPresaleReservedTokens;
        emit PresaleReservedTokensUpdated(_newPresaleReservedTokens);
    }

    //------------------------------------------------------//
    //
    //  Public function
    //
    //------------------------------------------------------//

    /// @notice buy tokens during presale
    /// @dev checks for whitelist and mints tokens to buyer
    /// @param _proofs array of merkle proofs to validate if user is whitelisted
    /// @param _buyer address of buyer
    /// @param _quantity amount of tokens to be bought
    function presaleBuy(
        bytes32[] calldata _proofs,
        address _buyer,
        uint256 _quantity
    ) external payable virtual {
        _presaleBuy(_proofs, _buyer, _quantity);
    }

    /// @notice get whitelist details
    /// @dev get whitelist merkle root and IPFS CID
    /// @return whitelist struct conatining whitelist details
    function getPresaleWhitelists()
        external
        view
        presaleAllowed
        returns (Whitelist memory whitelist)
    {
        return Whitelist(merkleRoot, whitelistCid);
    }

    /// @notice check if an address is whitelist or not
    /// @dev uses merkle proof to validate if account is whitelisted or not
    /// @param _proofs array of merkle proofs
    /// @param _account address which needs to be validated
    /// @return boolean is address whitelisted or not
    function isWhitelisted(bytes32[] calldata _proofs, address _account)
        public
        view
        returns (bool)
    {
        return _isWhitelisted(_proofs, _account);
    }

    /// @notice check if presale module is active or not
    /// @dev checks if presale module is active or not
    /// @return boolean is presale module active or not
    function isPresaleAllowed() public view returns (bool) {
        return presaleReservedTokens > 0;
    }

    /// @notice check if presale is whitelisted or not
    /// @dev if whitelisted, presale buy will check for whitelist else not
    /// @return boolean is presale whitelisted
    function isPresaleWhitelisted() public view returns (bool) {
        return isPresaleAllowed() && merkleRoot != bytes32(0);
    }

    /// @notice check if presale is live or not
    /// @dev only when presale active, tokens can be bought
    /// @return boolean is presale active or not
    function isPresaleActive() public view returns (bool) {
        return
            block.timestamp > presaleStartTime &&
            totalSupply() - reservedTokens < presaleReservedTokens &&
            block.timestamp < publicSaleStartTime;
    }

    //------------------------------------------------------//
    //
    //  Internal function
    //
    //------------------------------------------------------//

    /// @notice internal method to buy tokens during presale
    /// @dev invoked by presaleBuy and affiliatePresaleBuy
    /// @param _proofs array of merkle proofs to validate if user is whitelisted
    /// @param _buyer address of buyer
    /// @param _quantity amount of tokens to be bought
    function _presaleBuy(
        bytes32[] calldata _proofs,
        address _buyer,
        uint256 _quantity
    ) internal whenNotPaused presaleAllowed {
        require(isPresaleActive(), "PR:009");
        uint256 tokensMintedByUser = tokensMinted[_buyer];
        require(
            isPresaleWhitelisted() ? _isWhitelisted(_proofs, _buyer) : true,
            "PR:011"
        );
        require(
            totalSupply() - reservedTokens + _quantity <= presaleReservedTokens,
            "PR:013"
        );
        require(msg.value == (presalePrice * _quantity), "PR:010");
        require(_quantity <= maxPurchase, "PR:014");
        require(tokensMintedByUser + _quantity <= presaleMaxHolding, "PR:012");
        tokensMinted[_buyer] = tokensMintedByUser + _quantity;
        _manufacture(_buyer, _quantity);
    }

    /// @notice internal method to check if account if whitelisted or not
    /// @dev internally invoked by presale buy and isWhitelisted
    /// @param _proofs array of merkle proofs to validate if user is whitelisted
    /// @param _account address of buyer
    /// @return boolean is address whitelisted or not
    function _isWhitelisted(bytes32[] calldata _proofs, address _account)
        private
        view
        returns (bool)
    {
        bytes32 leaf = keccak256(abi.encodePacked(_account));
        return MerkleProofUpgradeable.verify(_proofs, merkleRoot, leaf);
    }

    /// @notice internal method to update whitelist details
    /// @dev invoked by updateWhitelist and setup
    /// @param _whitelist struct containing whitelist details
    function _setWhitelist(Whitelist memory _whitelist) private {
        merkleRoot = _whitelist.root;
        whitelistCid = _whitelist.cid;
        emit WhitelistUpdated(_whitelist.root, _whitelist.cid);
    }
}

