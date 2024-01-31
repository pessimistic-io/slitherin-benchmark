// SPDX-License-Identifier: Apache-2.0

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                           //
//                      _'                    AAA                                                                                            //
//                    !jz_                   A:::A                                                                                           //
//                 ;Lzzzz-                  A:::::A                                                                                          //
//              '1zzzzxzz'                 A:::::::A                                                                                         //
//            !xzzzzzzi~                  A:::::::::A             ssssssssss   ppppp   ppppppppp       eeeeeeeeeeee    nnnn  nnnnnnnn        //
//         ;izzzzzzj^`                   A:::::A:::::A          ss::::::::::s  p::::ppp:::::::::p    ee::::::::::::ee  n:::nn::::::::nn      //
//              `;^.`````               A:::::A A:::::A       ss:::::::::::::s p:::::::::::::::::p  e::::::eeeee:::::een::::::::::::::nn     //
//              -;;;;;;;-              A:::::A   A:::::A      s::::::ssss:::::spp::::::ppppp::::::pe::::::e     e:::::enn:::::::::::::::n    //
//           .;;;;;;;_                A:::::A     A:::::A      s:::::s  ssssss  p:::::p     p:::::pe:::::::eeeee::::::e  n:::::nnnn:::::n    //
//         ;;;;;;;;`                 A:::::AAAAAAAAA:::::A       s::::::s       p:::::p     p:::::pe:::::::::::::::::e   n::::n    n::::n    //
//      _;;;;;;;'                   A:::::::::::::::::::::A         s::::::s    p:::::p     p:::::pe::::::eeeeeeeeeee    n::::n    n::::n    //
//            ;{jjjjjjjjj          A:::::AAAAAAAAAAAAA:::::A  ssssss   s:::::s  p:::::p    p::::::pe:::::::e             n::::n    n::::n    //
//         `+IIIVVVVVVVVI`        A:::::A             A:::::A s:::::ssss::::::s p:::::ppppp:::::::pe::::::::e            n::::n    n::::n    //
//       ^sIVVVVVVVVVVVVI`       A:::::A               A:::::As::::::::::::::s  p::::::::::::::::p  e::::::::eeeeeeee    n::::n    n::::n    //
//    ~xIIIVVVVVVVVVVVVVI`      A:::::A                 A:::::As:::::::::::ss   p::::::::::::::pp    ee:::::::::::::e    n::::n    n::::n    //
//  -~~~;;;;;;;;;;;;;;;;;      AAAAAAA                   AAAAAAAsssssssssss     p::::::pppppppp        eeeeeeeeeeeeee    nnnnnn    nnnnnn    //
//                                                                              p:::::p                                                      //
//                                                                              p:::::p                                                      //
//                                                                             p:::::::p                                                     //
//                                                                             p:::::::p                                                     //
//                                                                             p:::::::p                                                     //
//                                                                             ppppppppp                                                     //
//                                                                                                                                           //
//  Website: https://aspenft.io/                                                                                                             //
//  Twitter: https://twitter.com/aspenft                                                                                                     //
//                                                                                                                                           //
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

pragma solidity ^0.8;

//  ==========  External imports    ==========
import "./Address.sol";

/// ========== Features ==========
import "./ERC2771ContextUpgradeable.sol";
import "./BaseAspenERC721DropV1.sol";

import "./FeeType.sol";
import "./MerkleProof.sol";

import "./errors_IErrors.sol";

import "./DropERC721DataTypes.sol";
import "./AspenERC721DropLogic.sol";

import "./TermsDataTypes.sol";
import "./TermsLogic.sol";

import "./AspenERC721DropStorage.sol";
import "./INFTSupply.sol";
import "./INFTMetadata.sol";

/// @title The AspenERC721Drop contract
contract AspenERC721Drop is AspenERC721DropStorage, BaseAspenERC721DropV1 {
    /// ================================
    /// =========== Libraries ==========
    /// ================================
    using StringsUpgradeable for uint256;
    using AspenERC721DropLogic for DropERC721DataTypes.ClaimData;
    using TermsLogic for TermsDataTypes.Terms;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    /// ====================================================
    /// ========== Constructor + initializer logic =========
    /// ====================================================
    constructor() {}

    /// @dev Initializes the contract, like a constructor.
    function initialize(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        address[] memory _trustedForwarders,
        address _saleRecipient,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        string memory _userAgreement,
        uint128 _platformFeeBps,
        address _platformFeeRecipient,
        address _drop1155DelegateLogic
    ) external initializer {
        // Initialize inherited contracts, most base-like -> most derived.
        __ReentrancyGuard_init();
        __ERC2771Context_init(_trustedForwarders);
        __ERC721_init(_name, _symbol);
        __DefaultOperatorFilterer_init();
        __EIP712_init(_name, "1.0.0");

        // Initialize this contract's state.
        __name = _name;
        __symbol = _symbol;
        claimData.royaltyRecipient = _royaltyRecipient;
        claimData.royaltyBps = uint16(_royaltyBps);
        _contractUri = _contractURI;
        _owner = _defaultAdmin;
        claimData.primarySaleRecipient = _saleRecipient;
        claimData.platformFeeRecipient = _platformFeeRecipient;
        claimData.platformFeeBps = uint16(_platformFeeBps);
        claimData.nextTokenIdToClaim = TOKEN_INDEX_OFFSET;
        claimData.nextTokenIdToMint = TOKEN_INDEX_OFFSET;
        // Agreement initialize
        termsData.termsURI = _userAgreement;
        // We set the terms version to 1 if there is an actual termsURL
        if (bytes(_userAgreement).length > 0) {
            termsData.termsVersion = 1;
            termsData.termsActivated = true;
        }
        delegateLogicContract = _drop1155DelegateLogic;
        operatorFiltererEnabled = true;

        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(MINTER_ROLE, _defaultAdmin);
        _setupRole(TRANSFER_ROLE, _defaultAdmin);
        _setupRole(TRANSFER_ROLE, address(0));
        _setupRole(ISSUER_ROLE, _defaultAdmin);

        emit OwnershipTransferred(address(0), _defaultAdmin);
    }

    fallback() external {
        // get facet from function selector
        address logic = delegateLogicContract;
        require(logic != address(0));
        // Execute external function from delegate logic contract using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), logic, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /// ============================================
    /// ========== Generic contract logic ==========
    /// ============================================
    /// @dev Returns the address of the current owner.
    function owner() public view override returns (address) {
        return _owner;
    }

    /// @dev Returns the name of the token.
    function name() public view override(ERC721Upgradeable, IERC721V2) returns (string memory) {
        return __name;
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view override(ERC721Upgradeable, IERC721V2) returns (string memory) {
        return __symbol;
    }

    /// @dev See {IERC721Enumerable-totalSupply}.
    function totalSupply() public view override(INFTSupplyV0, ERC721EnumerableUpgradeable) returns (uint256) {
        return ERC721EnumerableUpgradeable.totalSupply();
    }

    /// @dev See ERC 721 - Returns the URI for a given tokenId.
    function tokenURI(uint256 _tokenId)
        public
        view
        override(ERC721Upgradeable, IAspenNFTMetadataV1)
        isValidTokenId(_tokenId)
        returns (string memory)
    {
        return AspenERC721DropLogic.tokenURI(claimData, _tokenId);
    }

    /// @dev See ERC-2891 - Returns the royalty recipient and amount, given a tokenId and sale price.
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        virtual
        override
        isValidTokenId(tokenId)
        returns (address receiver, uint256 royaltyAmount)
    {
        return AspenERC721DropLogic.royaltyInfo(claimData, tokenId, salePrice);
    }

    /// @dev See ERC 165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(BaseAspenERC721DropV1, AspenERC721DropStorage)
        returns (bool)
    {
        return
            AspenERC721DropStorage.supportsInterface(interfaceId) ||
            BaseAspenERC721DropV1.supportsInterface(interfaceId) ||
            // Support ERC4906
            interfaceId == bytes4(0x49064906);
    }

    /// ======================================
    /// ============= Claim logic ============
    /// ======================================
    /// @dev Lets an account claim NFTs.
    function claim(
        address _receiver,
        uint256 _quantity,
        address _currency,
        uint256 _pricePerToken,
        bytes32[] calldata _proofs,
        uint256 _proofMaxQuantityPerTransaction
    ) external payable override nonReentrant {
        address msgSender = _msgSender();
        if (!(isTrustedForwarder(msg.sender) || msgSender == tx.origin)) revert Bot();
        if (claimIsPaused) revert ClaimPaused();

        (uint256[] memory tokens, AspenERC721DropLogic.InternalClaim memory internalClaim) = AspenERC721DropLogic
            .executeClaim(
                claimData,
                _quantity,
                _currency,
                _pricePerToken,
                _proofs,
                _proofMaxQuantityPerTransaction,
                _msgSender()
            );

        for (uint256 i = 0; i < tokens.length; i += 1) {
            _mint(_receiver, tokens[i]);
        }

        emit TokensClaimed(
            internalClaim.activeConditionId,
            msgSender,
            _receiver,
            internalClaim.tokenIdToClaim,
            _quantity,
            internalClaim.phaseId
        );
    }

    /// @dev Checks a request to claim NFTs against the active claim condition's criteria.
    function verifyClaim(
        uint256 _conditionId,
        address _claimer,
        uint256 _quantity,
        address _currency,
        uint256 _pricePerToken,
        bool verifyMaxQuantityPerTransaction
    ) public view override {
        AspenERC721DropLogic.verifyClaim(
            claimData,
            _conditionId,
            _claimer,
            _quantity,
            _currency,
            _pricePerToken,
            verifyMaxQuantityPerTransaction
        );
    }

    /// ======================================
    /// ============ Agreement ===============
    /// ======================================
    /// @notice by signing this transaction, you are confirming that you have read and agreed to the terms of use at `termsUrl`
    function acceptTerms() external override {
        termsData.acceptTerms(_msgSender());
        emit TermsAccepted(termsData.termsURI, termsData.termsVersion, _msgSender());
    }

    /// @notice returns the details of the terms
    /// @return termsURI - the URI of the terms
    /// @return termsVersion - the version of the terms
    /// @return termsActivated - the status of the terms
    function getTermsDetails()
        external
        view
        override
        returns (
            string memory termsURI,
            uint8 termsVersion,
            bool termsActivated
        )
    {
        return termsData.getTermsDetails();
    }

    /// @notice returns true if an address has accepted the terms
    function hasAcceptedTerms(address _address) external view override returns (bool hasAccepted) {
        hasAccepted = termsData.hasAcceptedTerms(_address);
    }

    /// @notice returns true if an address has accepted the terms
    function hasAcceptedTerms(address _address, uint8 _termsVersion) external view override returns (bool hasAccepted) {
        hasAccepted = termsData.hasAcceptedTerms(_address, _termsVersion);
    }

    /// ======================================
    /// ========== Getter functions ==========
    /// ======================================
    /// @dev Returns the sale recipient address.
    function primarySaleRecipient() external view override returns (address) {
        return claimData.primarySaleRecipient;
    }

    /// @dev Contract level metadata.
    function contractURI() external view override(IPublicMetadataV0) returns (string memory) {
        return _contractUri;
    }

    /// @dev Returns the platform fee recipient and bps.
    function getPlatformFeeInfo() external view override returns (address, uint16) {
        return (claimData.platformFeeRecipient, uint16(claimData.platformFeeBps));
    }

    /// @dev Returns the default royalty recipient and bps.
    function getDefaultRoyaltyInfo() external view override returns (address, uint16) {
        return (claimData.royaltyRecipient, uint16(claimData.royaltyBps));
    }

    /// @dev Returns the royalty recipient and bps for a particular token Id.
    function getRoyaltyInfoForToken(uint256 _tokenId)
        public
        view
        override
        isValidTokenId(_tokenId)
        returns (address, uint16)
    {
        return AspenERC721DropLogic.getRoyaltyInfoForToken(claimData, _tokenId);
    }

    /// @dev Returns the amount of stored baseURIs
    function getBaseURICount() external view returns (uint256) {
        return claimData.baseURIIndices.length;
    }

    /// @dev Gets the base URI indices
    function getBaseURIIndices() external view override returns (uint256[] memory) {
        return claimData.baseURIIndices;
    }

    /// @dev Returns the claim condition at the given uid.
    function getClaimConditionById(uint256 _conditionId) external view returns (ClaimCondition memory condition) {
        condition = AspenERC721DropLogic.getClaimConditionById(claimData, _conditionId);
    }

    /// @dev Expose the current active claim condition including claim limits
    function getActiveClaimConditions()
        external
        view
        override
        returns (
            ClaimCondition memory condition,
            uint256 conditionId,
            uint256 walletMaxClaimCount,
            uint256 tokenSupply,
            uint256 maxTotalSupply,
            bool isClaimPaused
        )
    {
        (condition, conditionId, walletMaxClaimCount, maxTotalSupply) = claimData.getActiveClaimConditions();
        isClaimPaused = claimIsPaused;
        tokenSupply = totalSupply();
    }

    /// @dev Expose the user specific limits related to the current active claim condition
    function getUserClaimConditions(address _claimer)
        external
        view
        override
        returns (
            uint256 conditionId,
            uint256 walletClaimedCount,
            uint256 walletClaimedCountInPhase,
            uint256 lastClaimTimestamp,
            uint256 nextValidClaimTimestamp
        )
    {
        return AspenERC721DropLogic.getUserClaimConditions(claimData, _claimer);
    }

    /**
     * @dev Indicates whether any token exist with a given id, or not.
     */
    function exists(uint256 _tokenId) public view isValidTokenId(_tokenId) returns (bool) {
        return _exists(_tokenId);
    }

    /// @dev Returns the offset for token IDs.
    function getSmallestTokenId() external pure override returns (uint8) {
        return TOKEN_INDEX_OFFSET;
    }

    /// ======================================
    /// ==== OS Default Operator Filterer ====
    /// ======================================
    modifier onlyAllowedOperator(address from) override {
        if (operatorFiltererEnabled) {
            // Check registry code length to facilitate testing in environments without a deployed registry.
            if (address(operatorFilterRegistry).code.length > 0) {
                // Allow spending tokens from addresses with balance
                // Note that this still allows listings and marketplaces with escrow to transfer tokens if transferred
                // from an EOA.
                if (from == msg.sender) {
                    _;
                    return;
                }
                if (!operatorFilterRegistry.isOperatorAllowed(address(this), msg.sender)) {
                    revert OperatorNotAllowed(msg.sender);
                }
            }
        }
        _;
    }

    modifier onlyAllowedOperatorApproval(address operator) override {
        if (operatorFiltererEnabled) {
            // Check registry code length to facilitate testing in environments without a deployed registry.
            if (address(operatorFilterRegistry).code.length > 0) {
                if (!operatorFilterRegistry.isOperatorAllowed(address(this), operator)) {
                    revert OperatorNotAllowed(operator);
                }
            }
        }
        _;
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override(ERC721Upgradeable, IERC721Upgradeable)
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId)
        public
        override(ERC721Upgradeable, IERC721Upgradeable)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    /// ======================================
    /// =========== Miscellaneous ============
    /// ======================================
    /// @dev Concrete implementation semantic version -
    ///         provided for completeness but not designed to be the point of dispatch
    function minorVersion() public pure override returns (uint256 minor, uint256 patch) {
        minor = 0;
        patch = 0;
    }

    /// @dev Burns `tokenId`. See {ERC721-_burn}.
    function burn(uint256 tokenId) public virtual {
        //solhint-disable-next-line max-line-length
        if (!(_isApprovedOrOwner(_msgSender(), tokenId))) revert InvalidPermission();
        _burn(tokenId);
        // Not strictly necessary since we shouldn't issue this token again
        claimData.tokenURIs[tokenId].sequenceNumber = 0;
    }

    /// @dev Provides a function to batch together multiple calls in a single external call.
    function multicall(bytes[] calldata data) external override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }

    function _msgSender() internal view virtual override returns (address sender) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData() internal view virtual override returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }
}

