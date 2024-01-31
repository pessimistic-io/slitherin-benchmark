// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./AspenERC1155DropStorage.sol";
import "./IDropClaimCondition.sol";
import "./BaseAspenERC1155DropV1.sol";

contract AspenERC1155DropDelegateLogic is
    AspenERC1155DropStorage,
    IDropClaimConditionV1,
    IDelegateBaseAspenERC1155DropV1
{
    /// ================================
    /// =========== Libraries ==========
    /// ================================
    using StringsUpgradeable for uint256;
    using TermsLogic for TermsDataTypes.Terms;
    using AspenERC1155DropLogic for DropERC1155DataTypes.ClaimData;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    constructor() {}

    function initialize() external initializer {}

    /// @dev See ERC 165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return AspenERC1155DropStorage.supportsInterface(interfaceId);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function setTokenURI(uint256 _tokenId, string memory _tokenURI)
        external
        virtual
        override
        isValidTokenId(_tokenId)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setTokenURI(_tokenId, _tokenURI, false);
    }

    function setPermantentTokenURI(uint256 _tokenId, string memory _tokenURI)
        external
        virtual
        override
        isValidTokenId(_tokenId)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setTokenURI(_tokenId, _tokenURI, true);
        emit PermanentURI(_tokenURI, _tokenId);
    }

    function _setTokenURI(
        uint256 _tokenId,
        string memory _tokenURI,
        bool isPermanent
    ) internal {
        if (claimData.totalSupply[_tokenId] <= 0) revert InvalidTokenId(_tokenId);
        if (claimData.tokenURIs[_tokenId].isPermanent) revert FrozenTokenMetadata(_tokenId);
        AspenERC1155DropLogic.setTokenURI(claimData, _tokenId, _tokenURI, isPermanent);
        emit TokenURIUpdated(_tokenId, _msgSender(), _tokenURI);
        emit URI(_tokenURI, _tokenId);
        emit MetadataUpdate(_tokenId);
    }

    /// ======================================
    /// =========== Minting logic ============
    /// ======================================
    /// @dev Lets an account with `MINTER_ROLE` lazy mint 'n' NFTs.
    ///        The URIs for each token is the provided `_baseURIForTokens` + `{tokenId}`.
    function lazyMint(uint256 _noOfTokenIds, string calldata _baseURIForTokens)
        external
        override
        onlyRole(MINTER_ROLE)
    {
        (uint256 startId, uint256 baseURIIndex) = AspenERC1155DropLogic.lazyMint(
            claimData,
            _noOfTokenIds,
            _baseURIForTokens
        );
        emit TokensLazyMinted(startId, baseURIIndex - TOKEN_INDEX_OFFSET, _baseURIForTokens);
    }

    /// ======================================
    /// ============= Issue logic ============
    /// ======================================
    /// @dev Lets an account claim a given quantity of NFTs, of a single tokenId.
    function issue(
        address _receiver,
        uint256 _tokenId,
        uint256 _quantity
    ) external override nonReentrant isValidTokenId(_tokenId) onlyRole(ISSUER_ROLE) {
        AspenERC1155DropLogic.verifyIssue(claimData, _tokenId, _quantity);

        _mint(_receiver, _tokenId, _quantity, "");

        emit TokensIssued(_tokenId, _msgSender(), _receiver, _quantity);
    }

    /// ======================================
    /// ============= Admin logic ============
    /// ======================================
    /// @dev Lets a contract admin (account with `DEFAULT_ADMIN_ROLE`) set claim conditions, for a tokenId.
    function setClaimConditions(
        uint256 _tokenId,
        ClaimCondition[] calldata _phases,
        bool _resetClaimEligibility
    ) external override isValidTokenId(_tokenId) onlyRole(DEFAULT_ADMIN_ROLE) {
        AspenERC1155DropLogic.setClaimConditions(claimData, _tokenId, _phases, _resetClaimEligibility);
        emit ClaimConditionsUpdated(_tokenId, _phases);
    }

    /// @dev Lets a contract admin set a new owner for the contract.
    function setOwner(address _newOwner) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        address _prevOwner = _owner;
        _owner = _newOwner;
        emit OwnershipTransferred(_prevOwner, _newOwner);
    }

    /// @dev Lets a contract admin set the token name and symbol.
    function setTokenNameAndSymbol(string calldata _name, string calldata _symbol)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        __name = _name;
        __symbol = _symbol;

        emit TokenNameAndSymbolUpdated(_msgSender(), __name, __symbol);
    }

    /// @dev Lets a contract admin set the recipient for all primary sales.
    function setPrimarySaleRecipient(address _saleRecipient) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _primarySaleRecipient = _saleRecipient;
        emit PrimarySaleRecipientUpdated(_saleRecipient);
    }

    /// @dev Lets a contract admin set the recipient for all primary sales.
    function setSaleRecipientForToken(uint256 _tokenId, address _saleRecipient)
        external
        isValidTokenId(_tokenId)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        claimData.saleRecipient[_tokenId] = _saleRecipient;
        emit SaleRecipientForTokenUpdated(_tokenId, _saleRecipient);
    }

    /// @dev Lets a contract admin update the platform fee recipient and bps
    function setPlatformFeeInfo(address _platformFeeRecipient, uint256 _platformFeeBps)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (!(_platformFeeBps <= AspenERC1155DropLogic.MAX_BPS)) revert MaxBps();

        claimData.platformFeeBps = uint16(_platformFeeBps);
        claimData.platformFeeRecipient = _platformFeeRecipient;

        emit PlatformFeeInfoUpdated(_platformFeeRecipient, _platformFeeBps);
    }

    /// @dev Lets a contract admin update the default royalty recipient and bps.
    function setDefaultRoyaltyInfo(address _royaltyRecipient, uint256 _royaltyBps)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        AspenERC1155DropLogic.setDefaultRoyaltyInfo(claimData, _royaltyRecipient, _royaltyBps);
        emit DefaultRoyalty(_royaltyRecipient, _royaltyBps);
    }

    /// @dev Lets a contract admin set the royalty recipient and bps for a particular token Id.
    function setRoyaltyInfoForToken(
        uint256 _tokenId,
        address _recipient,
        uint256 _bps
    ) external override isValidTokenId(_tokenId) onlyRole(DEFAULT_ADMIN_ROLE) {
        AspenERC1155DropLogic.setRoyaltyInfoForToken(claimData, _tokenId, _recipient, _bps);
        emit RoyaltyForToken(_tokenId, _recipient, _bps);
    }

    /// @dev Lets a contract admin set a claim count for a wallet.
    function setWalletClaimCount(
        uint256 _tokenId,
        address _claimer,
        uint256 _count
    ) external isValidTokenId(_tokenId) onlyRole(DEFAULT_ADMIN_ROLE) {
        claimData.walletClaimCount[_tokenId][_claimer] = _count;
        emit WalletClaimCountUpdated(_tokenId, _claimer, _count);
    }

    /// @dev Lets a contract admin set a maximum number of NFTs of a tokenId that can be claimed by any wallet.
    function setMaxWalletClaimCount(uint256 _tokenId, uint256 _count)
        external
        isValidTokenId(_tokenId)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        claimData.maxWalletClaimCount[_tokenId] = _count;
        emit MaxWalletClaimCountUpdated(_tokenId, _count);
    }

    /// @dev Lets a module admin set a max total supply for token.
    function setMaxTotalSupply(uint256 _tokenId, uint256 _maxTotalSupply)
        external
        isValidTokenId(_tokenId)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_maxTotalSupply != 0 && claimData.totalSupply[_tokenId] > _maxTotalSupply) {
            revert CrossedLimitMaxTotalSupply();
        }
        claimData.maxTotalSupply[_tokenId] = _maxTotalSupply;
        emit MaxTotalSupplyUpdated(_tokenId, _maxTotalSupply);
    }

    /// @dev Lets a contract admin set the URI for contract-level metadata.
    function setContractURI(string calldata _uri) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _contractUri = _uri;
        emit ContractURIUpdated(_msgSender(), _uri);
    }

    /// @dev Lets an account with `MINTER_ROLE` update base URI.
    function updateBaseURI(uint256 baseURIIndex, string calldata _baseURIForTokens)
        external
        override
        onlyRole(MINTER_ROLE)
    {
        if (bytes(claimData.baseURI[baseURIIndex + TOKEN_INDEX_OFFSET].uri).length == 0) revert BaseURIEmpty();

        claimData.uriSequenceCounter.increment();
        claimData.baseURI[baseURIIndex + TOKEN_INDEX_OFFSET].uri = _baseURIForTokens;
        claimData.baseURI[baseURIIndex + TOKEN_INDEX_OFFSET].sequenceNumber = claimData.uriSequenceCounter.current();

        emit BaseURIUpdated(baseURIIndex, _baseURIForTokens);
        emit BatchMetadataUpdate(
            baseURIIndex + TOKEN_INDEX_OFFSET - claimData.baseURI[baseURIIndex + TOKEN_INDEX_OFFSET].amountOfTokens,
            baseURIIndex
        );
    }

    /// @dev allows admin to pause / un-pause claims.
    function setClaimPauseStatus(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        claimIsPaused = _paused;
        emit ClaimPauseStatusUpdated(claimIsPaused);
    }

    /// @dev allows an admin to enable / disable the operator filterer.
    function setOperatorFiltererStatus(bool _enabled) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        operatorFiltererEnabled = _enabled;
        emit OperatorFilterStatusUpdated(operatorFiltererEnabled);
    }

    /// ======================================
    /// ============ Agreement ===============
    /// ======================================
    /// @notice allow an ISSUER to accept terms for an address
    function acceptTerms(address _acceptor) external override onlyRole(ISSUER_ROLE) {
        termsData.acceptTerms(_acceptor);
        emit TermsAcceptedForAddress(termsData.termsURI, termsData.termsVersion, _acceptor, _msgSender());
    }

    /// @notice allows an ISSUER to batch accept terms on behalf of multiple users
    function batchAcceptTerms(address[] calldata _acceptors) external onlyRole(ISSUER_ROLE) {
        for (uint256 i = 0; i < _acceptors.length; i++) {
            termsData.acceptTerms(_acceptors[i]);
            emit TermsAcceptedForAddress(termsData.termsURI, termsData.termsVersion, _acceptors[i], _msgSender());
        }
    }

    /// @notice activates / deactivates the terms of use.
    function setTermsActivation(bool _active) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        termsData.setTermsActivation(_active);
        emit TermsActivationStatusUpdated(_active);
    }

    /// @notice updates the term URI and pumps the terms version
    function setTermsURI(string calldata _termsURI) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        termsData.setTermsURI(_termsURI);
        emit TermsUpdated(_termsURI, termsData.termsVersion);
    }

    /// @notice allows anyone to accept terms on behalf of a user, as long as they provide a valid signature
    function acceptTerms(address _acceptor, bytes calldata _signature) external override {
        if (!_verifySignature(termsData, _acceptor, _signature)) revert SignatureVerificationFailed();
        termsData.acceptTerms(_acceptor);
        emit TermsWithSignatureAccepted(termsData.termsURI, termsData.termsVersion, _acceptor, _signature);
    }

    /// @notice verifies a signature
    /// @dev this function takes the signers address and the signature signed with their private key.
    ///     ECDSA checks whether a hash of the message was signed by the user's private key.
    ///     If yes, the _to address == ECDSA's returned address
    function _verifySignature(
        TermsDataTypes.Terms storage termsData,
        address _acceptor,
        bytes memory _signature
    ) internal view returns (bool) {
        if (_signature.length == 0) return false;
        bytes32 hash = _hashMessage(termsData, _acceptor);
        address signer = ECDSAUpgradeable.recover(hash, _signature);
        return signer == _acceptor;
    }

    /// @dev this function hashes the terms url and message
    function _hashMessage(TermsDataTypes.Terms storage termsData, address _acceptor) private view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(MESSAGE_HASH, _acceptor, keccak256(bytes(termsData.termsURI)), termsData.termsVersion)
                )
            );
    }
}

