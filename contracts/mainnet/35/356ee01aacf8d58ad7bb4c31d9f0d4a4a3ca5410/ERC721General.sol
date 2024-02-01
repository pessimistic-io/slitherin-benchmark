// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./ERC721Base.sol";
import "./MetadataEncryption.sol";
import "./IPostTransfer.sol";
import "./IPostBurn.sol";
import "./IERC721GeneralMint.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./MarketplaceFilterer.sol";

/**
 * @title Generalized ERC721
 * @author ishan@highlight.xyz
 * @notice Generalized NFT smart contract
 */
contract ERC721General is
    ERC721Base,
    ERC721URIStorageUpgradeable,
    MetadataEncryption,
    IERC721GeneralMint,
    MarketplaceFilterer
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Total tokens minted
     */
    uint256 public supply;

    /**
     * @notice Contract metadata
     */
    string public contractURI;

    /**
     * @notice Limit the supply to take advantage of over-promising in summation with multiple mint vectors
     */
    uint256 public limitSupply;

    /**
     * @notice Emitted when uris are set for tokens
     * @param ids IDs of tokens to set uris for
     * @param uris Uris to set on tokens
     */
    event TokenURIsSet(uint256[] ids, string[] uris);

    /**
     * @notice Emitted when limit supply is set
     * @param newLimitSupply Limit supply to set
     */
    event LimitSupplySet(uint256 indexed newLimitSupply);

    /**
     * @notice Emitted when hashed metadata config is set
     * @param hashedURIData Hashed uri data
     * @param hashedRotationData Hashed rotation key
     * @param _supply Supply of tokens to mint w/ reveal
     */
    event HashedMetadataConfigSet(bytes hashedURIData, bytes hashedRotationData, uint256 indexed _supply);

    /**
     * @notice Emitted when metadata is revealed
     * @param key Key used to decode hashed data
     * @param newRotationKey Actual rotation key to be used
     */
    event Revealed(bytes key, uint256 newRotationKey);

    /**
     * @notice Initialize the contract
     * @param creator Creator/owner of contract
     * @param _contractURI Contract metadata
     * @param defaultRoyalty Default royalty object for contract (optional)
     * @param _defaultTokenManager Default token manager for contract (optional)
     * @param _name Name of token edition
     * @param _symbol Symbol of the token edition
     * @param trustedForwarder Trusted minimal forwarder
     * @param initialMinter Initial minter to register
     * @param newBaseURI Base URI for contract
     * @param _limitSupply Initial limit supply
     * @param useMarketplaceFiltererRegistry Denotes whether to use marketplace filterer registry
     */
    function initialize(
        address creator,
        string memory _contractURI,
        IRoyaltyManager.Royalty memory defaultRoyalty,
        address _defaultTokenManager,
        string memory _name,
        string memory _symbol,
        address trustedForwarder,
        address initialMinter,
        string memory newBaseURI,
        uint256 _limitSupply,
        bool useMarketplaceFiltererRegistry
    ) external initializer nonReentrant {
        _initialize(
            creator,
            _contractURI,
            defaultRoyalty,
            _defaultTokenManager,
            _name,
            _symbol,
            trustedForwarder,
            initialMinter,
            newBaseURI,
            _limitSupply,
            useMarketplaceFiltererRegistry
        );
    }

    /**
     * @notice Initialize the contract
     * @param data Data to initialize the contract
     * @ param creator Creator/owner of contract
     * @ param _contractURI Contract metadata
     * @ param defaultRoyalty Default royalty object for contract (optional)
     * @ param _defaultTokenManager Default token manager for contract (optional)
     * @ param _name Name of token edition
     * @ param _symbol Symbol of the token edition
     * @ param trustedForwarder Trusted minimal forwarder
     * @ param initialMinter Initial minter to register
     * @ param newBaseURI Base URI for contract
     * @ param _limitSupply Initial limit supply
     * @ param useMarketplaceFiltererRegistry Denotes whether to use marketplace filterer registry
     */
    function initialize(bytes calldata data) external initializer nonReentrant {
        (
            address creator,
            string memory _contractURI,
            IRoyaltyManager.Royalty memory defaultRoyalty,
            address _defaultTokenManager,
            string memory _name,
            string memory _symbol,
            address trustedForwarder,
            address initialMinter,
            string memory newBaseURI,
            uint256 _limitSupply,
            bool useMarketplaceFiltererRegistry
        ) = abi.decode(
                data,
                (
                    address,
                    string,
                    IRoyaltyManager.Royalty,
                    address,
                    string,
                    string,
                    address,
                    address,
                    string,
                    uint256,
                    bool
                )
            );

        _initialize(
            creator,
            _contractURI,
            defaultRoyalty,
            _defaultTokenManager,
            _name,
            _symbol,
            trustedForwarder,
            initialMinter,
            newBaseURI,
            _limitSupply,
            useMarketplaceFiltererRegistry
        );
    }

    /**
     * @notice See {IERC721GeneralMint-mintOneToOneRecipient}
     */
    function mintOneToOneRecipient(address recipient) external onlyMinter nonReentrant returns (uint256) {
        require(_mintFrozen == 0, "Mint frozen");

        uint256 tempSupply = supply;
        tempSupply++;
        _requireLimitSupply(tempSupply);

        _mint(recipient, tempSupply);
        supply = tempSupply;

        return tempSupply;
    }

    /**
     * @notice See {IERC721GeneralMint-mintAmountToOneRecipient}
     */
    function mintAmountToOneRecipient(address recipient, uint256 amount) external onlyMinter nonReentrant {
        require(_mintFrozen == 0, "Mint frozen");
        uint256 tempSupply = supply; // cache

        for (uint256 i = 0; i < amount; i++) {
            tempSupply++;
            _mint(recipient, tempSupply);
        }

        _requireLimitSupply(tempSupply);
        supply = tempSupply;
    }

    /**
     * @notice See {IERC721GeneralMint-mintOneToMultipleRecipients}
     */
    function mintOneToMultipleRecipients(address[] calldata recipients) external onlyMinter nonReentrant {
        require(_mintFrozen == 0, "Mint frozen");
        uint256 recipientsLength = recipients.length;
        uint256 tempSupply = supply; // cache

        for (uint256 i = 0; i < recipientsLength; i++) {
            tempSupply++;
            _mint(recipients[i], tempSupply);
        }

        _requireLimitSupply(tempSupply);
        supply = tempSupply;
    }

    /**
     * @notice See {IERC721GeneralMint-mintSameAmountToMultipleRecipients}
     */
    function mintSameAmountToMultipleRecipients(address[] calldata recipients, uint256 amount)
        external
        onlyMinter
        nonReentrant
    {
        require(_mintFrozen == 0, "Mint frozen");
        uint256 recipientsLength = recipients.length;
        uint256 tempSupply = supply; // cache

        for (uint256 i = 0; i < recipientsLength; i++) {
            for (uint256 j = 0; j < amount; j++) {
                tempSupply++;
                _mint(recipients[i], tempSupply);
            }
        }

        _requireLimitSupply(tempSupply);
        supply = tempSupply;
    }

    /**
     * @notice See {IERC721GeneralMint-mintSpecificTokenToOneRecipient}
     */
    function mintSpecificTokenToOneRecipient(address recipient, uint256 tokenId) external onlyMinter nonReentrant {
        require(_mintFrozen == 0, "Mint frozen");

        uint256 tempSupply = supply;
        tempSupply++;

        uint256 _limitSupply = limitSupply;
        if (_limitSupply != 0) {
            require(tokenId <= _limitSupply, "Token not in range");
        }

        _mint(recipient, tokenId);
        supply = tempSupply;
    }

    /**
     * @notice See {IERC721GeneralMint-mintSpecificTokensToOneRecipient}
     */
    function mintSpecificTokensToOneRecipient(address recipient, uint256[] calldata tokenIds)
        external
        onlyMinter
        nonReentrant
    {
        require(_mintFrozen == 0, "Mint frozen");

        uint256 tempSupply = supply;

        uint256 tokenIdsLength = tokenIds.length;
        uint256 _limitSupply = limitSupply;
        if (_limitSupply == 0) {
            // don't check that token id is within range, since _limitSupply being 0 implies unlimited range
            for (uint256 i = 0; i < tokenIdsLength; i++) {
                _mint(recipient, tokenIds[i]);
                tempSupply++;
            }
        } else {
            // check that token id is within range
            for (uint256 i = 0; i < tokenIdsLength; i++) {
                require(tokenIds[i] <= limitSupply, "Token not in range");
                _mint(recipient, tokenIds[i]);
                tempSupply++;
            }
        }

        supply = tempSupply;
    }

    /**
     * @notice Override base URI system for select tokens, with custom per-token metadata
     * @param ids IDs of tokens to override base uri system for with custom uris
     * @param uris Custom uris
     */
    function setTokenURIs(uint256[] calldata ids, string[] calldata uris) external nonReentrant {
        uint256 idsLength = ids.length;
        require(idsLength == uris.length, "Mismatched array lengths");

        for (uint256 i = 0; i < idsLength; i++) {
            _setTokenURI(ids[i], uris[i]);
        }

        emit TokenURIsSet(ids, uris);
    }

    /**
     * @notice Set base uri
     * @param newBaseURI New base uri to set
     */
    function setBaseURI(string calldata newBaseURI) external nonReentrant {
        require(bytes(newBaseURI).length > 0, "Empty string");

        address _manager = defaultManager;

        if (_manager == address(0)) {
            require(_msgSender() == owner(), "Not owner");
        } else {
            require(
                ITokenManager(_manager).canUpdateMetadata(_msgSender(), 0, bytes(newBaseURI)),
                "Can't update base uri"
            );
        }

        _setBaseURI(newBaseURI);
    }

    /**
     * @notice Set limit supply
     * @param _limitSupply Limit supply to set
     */
    function setLimitSupply(uint256 _limitSupply) external onlyOwner nonReentrant {
        // allow it to be 0, for post-mint
        limitSupply = _limitSupply;

        emit LimitSupplySet(_limitSupply);
    }

    /**
     * @notice Configure a reveal mint metadata
     * @param hashedURIData Hashed uri data
     * @param hashedRotationData Hashed rotation key
     * @param _supply Supply of tokens to mint w/ reveal
     */
    function setHashedMetadataConfig(
        bytes calldata hashedURIData,
        bytes calldata hashedRotationData,
        uint256 _supply
    ) external onlyOwner nonReentrant {
        (bytes memory encryptedURI, bytes32 provenanceHashURI) = abi.decode(hashedURIData, (bytes, bytes32));

        if (encryptedURI.length != 0 && provenanceHashURI != "") {
            _hashedBaseURIData = hashedURIData;
        }

        (bytes memory encryptedRotationKey, bytes32 provenanceHashRotation) = abi.decode(
            hashedRotationData,
            (bytes, bytes32)
        );

        if (encryptedRotationKey.length != 0 && provenanceHashRotation != "") {
            _hashedRotationKeyData = hashedRotationData;
        }

        supply = _supply;

        emit HashedMetadataConfigSet(hashedURIData, hashedRotationData, _supply);
    }

    /**
     * @notice Reveal metadata by decrypting encrypted base uri, and encrypted rotation key, appending the two
     * @param _key Encoded metadata decoder
     */
    function reveal(bytes calldata _key) external onlyOwner nonReentrant {
        bytes memory uriData = _hashedBaseURIData;
        (bytes memory encryptedURI, bytes32 provenanceHashURI) = abi.decode(uriData, (bytes, bytes32));

        require(encryptedURI.length != 0, "nothing to reveal");

        string memory revealedURI = string(encryptDecrypt(encryptedURI, _key));

        require(keccak256(abi.encodePacked(revealedURI, _key, block.chainid)) == provenanceHashURI, "Incorrect key");

        baseURI = revealedURI;
        delete _hashedBaseURIData;

        bytes memory rotationData = _hashedRotationKeyData;
        (bytes memory encryptedRotationKey, bytes32 provenanceHashRotation) = abi.decode(
            rotationData,
            (bytes, bytes32)
        );

        require(encryptedRotationKey.length != 0, "nothing to reveal");

        uint256 revealedRotation = _sliceUint(encryptDecrypt(encryptedRotationKey, _key), 0);

        require(
            keccak256(abi.encodePacked(revealedRotation, _key, block.chainid)) == provenanceHashRotation,
            "Incorrect key"
        );

        _rotationKey = revealedRotation;
        delete _hashedRotationKeyData;

        emit Revealed(_key, revealedRotation);
    }

    /**
     * @notice Total supply of NFTs on the contract
     */
    function totalSupply() external view returns (uint256) {
        return supply;
    }

    /**
     * @notice See {IERC721-transferFrom}. Overrides default behaviour to check associated tokenManager.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override nonReentrant onlyAllowedOperator(from) {
        ERC721Upgradeable.transferFrom(from, to, tokenId);

        address _manager = tokenManager(tokenId);
        if (_manager != address(0) && IERC165Upgradeable(_manager).supportsInterface(type(IPostTransfer).interfaceId)) {
            IPostTransfer(_manager).postTransferFrom(_msgSender(), from, to, tokenId);
        }
    }

    /**
     * @notice See {IERC721-safeTransferFrom}. Overrides default behaviour to check associated tokenManager.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual override nonReentrant onlyAllowedOperator(from) {
        ERC721Upgradeable.safeTransferFrom(from, to, tokenId, data);

        address _manager = tokenManager(tokenId);
        if (_manager != address(0) && IERC165Upgradeable(_manager).supportsInterface(type(IPostTransfer).interfaceId)) {
            IPostTransfer(_manager).postSafeTransferFrom(_msgSender(), from, to, tokenId, data);
        }
    }

    /**
     * @notice See {IERC721-setApprovalForAll}.
     *         Overrides default behaviour to check MarketplaceFilterer allowed operators.
     */
    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    /**
     * @notice See {IERC721-approve}.
     *         Overrides default behaviour to check MarketplaceFilterer allowed operators.
     */
    function approve(address operator, uint256 tokenId) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    /**
     * @notice See {IERC721-burn}. Overrides default behaviour to check associated tokenManager.
     */
    function burn(uint256 tokenId) public nonReentrant {
        address _manager = tokenManager(tokenId);

        if (_manager != address(0) && IERC165Upgradeable(_manager).supportsInterface(type(IPostBurn).interfaceId)) {
            address owner = ownerOf(tokenId);
            IPostBurn(_manager).postBurn(_msgSender(), owner, tokenId);
        } else {
            // default to restricting burn to owner or operator if a valid TM isn't present
            require(_isApprovedOrOwner(_msgSender(), tokenId), "Not owner or operator");
        }

        _burn(tokenId);
    }

    /**
     * @notice Overrides tokenURI to first rotate the token id
     * @param tokenId ID of token to get uri for
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        uint256 rotatedTokenId = tokenId + _rotationKey;
        if (rotatedTokenId > supply) {
            rotatedTokenId = rotatedTokenId - supply;
        }
        return ERC721URIStorageUpgradeable.tokenURI(rotatedTokenId);
    }

    /**
     * @notice See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165Upgradeable, ERC721Upgradeable)
        returns (bool)
    {
        return ERC721Upgradeable.supportsInterface(interfaceId);
    }

    /**
     * @notice Used for meta-transactions
     */
    function _msgSender() internal view override(ERC721Base, ContextUpgradeable) returns (address sender) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /**
     * @notice Used for meta-transactions
     */
    function _msgData() internal view override(ERC721Base, ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    /**
     * @notice Override base URI system for select tokens, with custom per-token metadata
     * @param tokenId Token to set uri for
     * @param _uri Uri to set on token
     */
    function _setTokenURI(uint256 tokenId, string calldata _uri) private {
        address _manager = tokenManager(tokenId);
        address msgSender = _msgSender();

        address tempOwner = owner();
        if (_manager == address(0)) {
            require(msgSender == tempOwner, "Not owner");
        } else {
            require(ITokenManager(_manager).canUpdateMetadata(msgSender, tokenId, bytes(_uri)), "Can't update");
        }

        _tokenURIs[tokenId] = _uri;
    }

    /**
     * @notice Initialize the contract
     * @param creator Creator/owner of contract
     * @param _contractURI Contract metadata
     * @param defaultRoyalty Default royalty object for contract (optional)
     * @param _defaultTokenManager Default token manager for contract (optional)
     * @param _name Name of token edition
     * @param _symbol Symbol of the token edition
     * @param trustedForwarder Trusted minimal forwarder
     * @param initialMinter Initial minter to register
     * @param newBaseURI Base URI for contract
     * @param _limitSupply Initial limit supply
     * @param useMarketplaceFiltererRegistry Denotes whether to use marketplace filterer registry
     */
    function _initialize(
        address creator,
        string memory _contractURI,
        IRoyaltyManager.Royalty memory defaultRoyalty,
        address _defaultTokenManager,
        string memory _name,
        string memory _symbol,
        address trustedForwarder,
        address initialMinter,
        string memory newBaseURI,
        uint256 _limitSupply,
        bool useMarketplaceFiltererRegistry
    ) private {
        __ERC721URIStorage_init();
        __ERC721Base_initialize(creator, defaultRoyalty, _defaultTokenManager);
        __ERC2771ContextUpgradeable__init__(trustedForwarder);
        __ERC721_init(_name, _symbol);
        __MarketplaceFilterer__init__(useMarketplaceFiltererRegistry);
        _minters.add(initialMinter);
        contractURI = _contractURI;

        if (bytes(newBaseURI).length > 0) {
            _setBaseURI(newBaseURI);
        }

        if (_limitSupply > 0) {
            limitSupply = _limitSupply;

            emit LimitSupplySet(_limitSupply);
        }
    }

    /**
     * @notice Require the new supply of tokens after mint to be less than limit supply
     * @param newSupply New supply
     */
    function _requireLimitSupply(uint256 newSupply) private view {
        uint256 _limitSupply = limitSupply;
        require(_limitSupply == 0 || newSupply <= _limitSupply, "Over limit supply");
    }
}

