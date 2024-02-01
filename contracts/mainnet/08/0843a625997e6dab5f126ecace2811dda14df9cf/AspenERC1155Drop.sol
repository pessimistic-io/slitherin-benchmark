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
import "./BaseAspenERC1155DropV1.sol";

import "./FeeType.sol";
import "./MerkleProof.sol";

import "./errors_IErrors.sol";

import "./DropERC1155DataTypes.sol";
import "./AspenERC1155DropLogic.sol";

import "./TermsDataTypes.sol";
import "./TermsLogic.sol";

import "./AspenERC1155DropStorage.sol";
import "./IDropClaimCondition.sol";

/// @title The AspenERC1155Drop contract
contract AspenERC1155Drop is AspenERC1155DropStorage, BaseAspenERC1155DropV1 {
    /// ================================
    /// =========== Libraries ==========
    /// ================================
    using StringsUpgradeable for uint256;
    using TermsLogic for TermsDataTypes.Terms;
    using AspenERC1155DropLogic for DropERC1155DataTypes.ClaimData;

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
        __ERC2771Context_init_unchained(_trustedForwarders);
        __ERC1155_init_unchained("");
        __DefaultOperatorFilterer_init();
        __EIP712_init(_name, "1.0.0");

        // Initialize this contract's state.
        __name = _name;
        __symbol = _symbol;
        claimData.royaltyRecipient = _royaltyRecipient;
        claimData.royaltyBps = uint16(_royaltyBps);
        _primarySaleRecipient = _saleRecipient;
        _owner = _defaultAdmin;
        _contractUri = _contractURI;
        claimData.platformFeeRecipient = _platformFeeRecipient;
        claimData.platformFeeBps = uint16(_platformFeeBps);
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
    function name() public view override returns (string memory) {
        return __name;
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return __symbol;
    }

    /// @dev See ERC 1155 - Returns the URI for a given tokenId.
    function uri(uint256 _tokenId)
        public
        view
        virtual
        override(ERC1155Upgradeable, IAspenSFTMetadataV1)
        isValidTokenId(_tokenId)
        returns (string memory _tokenURI)
    {
        return AspenERC1155DropLogic.tokenURI(claimData, _tokenId);
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
        return AspenERC1155DropLogic.royaltyInfo(claimData, tokenId, salePrice);
    }

    /// @dev See ERC 165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(BaseAspenERC1155DropV1, AspenERC1155DropStorage)
        returns (bool)
    {
        return
            AspenERC1155DropStorage.supportsInterface(interfaceId) ||
            BaseAspenERC1155DropV1.supportsInterface(interfaceId) ||
            // Support ERC4906
            interfaceId == bytes4(0x49064906);
    }

    // More pointless yet required overrides
    function totalSupply(uint256 _tokenId) public view override isValidTokenId(_tokenId) returns (uint256) {
        return claimData.totalSupply[_tokenId];
    }

    function exists(uint256 _tokenId) public view override isValidTokenId(_tokenId) returns (bool) {
        return claimData.totalSupply[_tokenId] > 0;
    }

    /// @dev returns the total number of unique tokens in existence.
    function getLargestTokenId() public view override returns (uint256) {
        return claimData.nextTokenIdToMint - TOKEN_INDEX_OFFSET;
    }

    /// @dev Returns the offset for token IDs.
    function getSmallestTokenId() external pure override returns (uint8) {
        return TOKEN_INDEX_OFFSET;
    }

    /// ======================================
    /// ============= Claim logic ============
    /// ======================================
    /// @dev Lets an account claim a given quantity of NFTs, of a single tokenId.
    function claim(
        address _receiver,
        uint256 _tokenId,
        uint256 _quantity,
        address _currency,
        uint256 _pricePerToken,
        bytes32[] calldata _proofs,
        uint256 _proofMaxQuantityPerTransaction
    ) external payable override nonReentrant isValidTokenId(_tokenId) {
        address msgSender = _msgSender();
        if (!(isTrustedForwarder(msg.sender) || msgSender == tx.origin)) revert Bot();
        if (claimIsPaused) revert ClaimPaused();

        AspenERC1155DropLogic.InternalClaim memory internalClaim = AspenERC1155DropLogic.executeClaim(
            claimData,
            _tokenId,
            _quantity,
            _currency,
            _pricePerToken,
            _proofs,
            _proofMaxQuantityPerTransaction,
            msgSender,
            _primarySaleRecipient
        );
        _mint(_receiver, _tokenId, _quantity, "");
        emit TokensClaimed(
            internalClaim.activeConditionId,
            _tokenId,
            msgSender,
            _receiver,
            _quantity,
            internalClaim.phaseId
        );
    }

    /// @dev Checks a request to claim NFTs against the active claim condition's criteria.
    function verifyClaim(
        uint256 _conditionId,
        address _claimer,
        uint256 _tokenId,
        uint256 _quantity,
        address _currency,
        uint256 _pricePerToken,
        bool verifyMaxQuantityPerTransaction
    ) public view override isValidTokenId(_tokenId) {
        AspenERC1155DropLogic.verifyClaim(
            claimData,
            _conditionId,
            _claimer,
            _tokenId,
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
    /// @dev Contract level metadata.
    function contractURI() external view override(IPublicMetadataV0) returns (string memory) {
        return _contractUri;
    }

    /// @dev Returns the sale recipient address.
    function primarySaleRecipient() external view override returns (address) {
        return _primarySaleRecipient;
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
        return AspenERC1155DropLogic.getRoyaltyInfoForToken(claimData, _tokenId);
    }

    /// @dev Returns the claim condition at the given uid.
    function getClaimConditionById(uint256 _tokenId, uint256 _conditionId)
        external
        view
        isValidTokenId(_tokenId)
        returns (ClaimCondition memory condition)
    {
        condition = AspenERC1155DropLogic.getClaimConditionById(claimData, _tokenId, _conditionId);
    }

    /// @dev Expose the current active claim condition including claim limits
    function getActiveClaimConditions(uint256 _tokenId)
        external
        view
        override
        isValidTokenId(_tokenId)
        returns (
            ClaimCondition memory condition,
            uint256 conditionId,
            uint256 walletMaxClaimCount,
            uint256 tokenSupply,
            uint256 maxTotalSupply,
            bool isClaimPaused
        )
    {
        (condition, conditionId, walletMaxClaimCount, maxTotalSupply) = AspenERC1155DropLogic.getActiveClaimConditions(
            claimData,
            _tokenId
        );
        isClaimPaused = claimIsPaused;
        tokenSupply = totalSupply(_tokenId);
    }

    /// @dev Expose the user specific limits related to the current active claim condition
    function getUserClaimConditions(uint256 _tokenId, address _claimer)
        external
        view
        override
        isValidTokenId(_tokenId)
        returns (
            uint256 conditionId,
            uint256 walletClaimedCount,
            uint256 walletClaimedCountInPhase,
            uint256 lastClaimTimestamp,
            uint256 nextValidClaimTimestamp
        )
    {
        return AspenERC1155DropLogic.getUserClaimConditions(claimData, _tokenId, _claimer);
    }

    /// @dev Gets the base URI indices
    function getBaseURIIndices() external view override returns (uint256[] memory) {
        return claimData.baseURIIndices;
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
        override(ERC1155Upgradeable, IERC1155Upgradeable)
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes memory data
    ) public override(ERC1155Upgradeable, IERC1155Upgradeable) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override(ERC1155Upgradeable, IERC1155Upgradeable) onlyAllowedOperator(from) {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
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

    /// @dev Lets a token owner burn the tokens they own (i.e. destroy for good)
    function burn(
        address account,
        uint256 id,
        uint256 value
    ) public virtual {
        if (!(account == _msgSender() || isApprovedForAll(account, _msgSender()))) revert InvalidPermission();
        _burn(account, id, value);
    }

    /// @dev Lets a token owner burn multiple tokens they own at once (i.e. destroy for good)
    function burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory values
    ) public virtual {
        if (!(account == _msgSender() || isApprovedForAll(account, _msgSender()))) revert InvalidPermission();
        _burnBatch(account, ids, values);
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

    // FIXME: well, fix solc, this is a horrible hack to make these library-emitted events appear in the ABI for this
    //   contract
    function __termsNotAccepted() external pure {
        revert TermsNotAccepted(address(0), "", uint8(0));
    }
}

