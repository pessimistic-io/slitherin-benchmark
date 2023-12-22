// SPDX-License-Identifier: BUSL 1.0
// Metadrop Contracts (v2.1.0)

/**
 *
 * @title NFTByMetadrop.sol. This contract is the clonable template contract for
 * all metadrop NFT deployments.
 *
 * @author metadrop https://metadrop.com/
 *
 * @notice This contract does not include logic associated with the primary
 * sale of the NFT, that functionality being provided by other contracts within
 * the metadrop platform (e.g. an auction, or a public and list based sale) that
 * form a suite of primary sale modules.
 *
 */

pragma solidity 0.8.19;

import {Strings} from "./Strings.sol";
import {DefaultOperatorFilterer, CANONICAL_CORI_SUBSCRIPTION} from "./DefaultOperatorFilterer.sol";
import {ERC2981} from "./ERC2981.sol";
import {ERC721AM} from "./ERC721AM.sol";
import {INFTByMetadrop} from "./INFTByMetadrop.sol";
import {IDropFactory} from "./IDropFactory.sol";
import {PrimaryVestingByMetadrop} from "./PrimaryVestingByMetadrop.sol";
import {ONFT721Core} from "./ONFT721Core.sol";
import {IPrimarySaleModule} from "./IPrimarySaleModule.sol";
import {EPS4907} from "./EPS4907.sol";

contract NFTByMetadrop is
  ERC721AM,
  INFTByMetadrop,
  DefaultOperatorFilterer,
  PrimaryVestingByMetadrop,
  ERC2981,
  ONFT721Core,
  EPS4907
{
  using Strings for uint256;

  // Slot 1:
  //    160
  //     32
  //     24
  //      8
  //      8
  //      8
  //      8
  //      8
  // ------
  //    256
  // ------
  //
  // Factory address
  address public factory;
  // The most recent assistance request timestamp (note default is 0):
  uint32 public assistanceRequestTimeStamp;
  // The period of time (in seconds) that an assistance request is open for:
  uint24 public assistanceRequestWindowInSeconds;
  // Bool that controls initialisation and only allows it to occur ONCE. This is
  // needed as this contract is clonable, threfore the constructor is not called
  // on cloned instances. We setup state of this contract through the initialise
  // function.
  bool public initialised;
  // Is metadata locked?:
  bool public metadataLocked;
  // Minting complete confirmation
  bool public mintingComplete;
  // Are we revealed:
  bool public collectionRevealed;
  // Is this a single metadata collection (e.g. an open edition with one json / image):
  bool public singleMetadataCollection;

  //Slots 2 to n: 256
  //
  // URI details:
  string public preRevealURI;
  string public revealedURI;
  // Proof and VRF results for metadata reveal:
  bytes32 public positionProof;
  uint256 public vrfStartPosition;

  // Valid primary market addresses
  mapping(address => bool) public validPrimaryMarketAddress;

  /** ====================================================================================================================
   *                                              CONSTRUCTOR AND INTIIALISE
   * =====================================================================================================================
   */
  /** ____________________________________________________________________________________________________________________
   *                                                                                                        -->CONSTRUCTOR
   * @dev constructor           The constructor is not called when the contract is cloned. In this
   *                            constructor we just setup default values and set the template contract to initialised.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param epsRegister_        The EPS register address (0x888888888888660F286A7C06cfa3407d09af44B2 on most chains)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param lzEndpoint_         The LZ endpoint for this chain
   *                            (see https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param wethAddress_        WETH address on this chain
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  constructor(
    address epsRegister_,
    address lzEndpoint_,
    address wethAddress_
  )
    PrimaryVestingByMetadrop(wethAddress_)
    ONFT721Core(lzEndpoint_)
    EPS4907(epsRegister_)
  {
    // Initialise this template instance:
    _initialiseERC721AM("", "", 0, false, 0);

    initialised = true;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                         -->INITIALISE
   * @dev (function) initialiseNFT  Load configuration into storage for a new instance.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param projectOwner_            The project owner for this drop. Sets the project admin AccessControl role
   * ---------------------------------------------------------------------------------------------------------------------
   * @param primarySaleModules_      The primary sale modules for this drop. These are the contract addresses that are
   *                                 authorised to call mint on this contract.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param nftModule_               Configuration of this collection
   * ---------------------------------------------------------------------------------------------------------------------
   * @param royaltyInfo_             Details of royalties for this collection
   * ---------------------------------------------------------------------------------------------------------------------
   * @param collectionURIs_          The URIs for this collection
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function initialiseNFT(
    address projectOwner_,
    PrimarySaleModuleInstance[] calldata primarySaleModules_,
    NFTModuleConfig calldata nftModule_,
    RoyaltyDetails memory royaltyInfo_,
    string[2] calldata collectionURIs_
  ) public {
    // This clone instance can only be initialised ONCE
    if (initialised) _revert(AlreadyInitialised.selector);
    // Set this clone to initialised
    initialised = true;

    // If an inheriting token contract is deployed to a network without the registry deployed, the modifier
    // will not revert, but the contract will need to be registered with the registry once it is deployed in
    // order for the modifier to filter addresses.
    if (address(OPERATOR_FILTER_REGISTRY).code.length > 0) {
      OPERATOR_FILTER_REGISTRY.registerAndSubscribe(
        address(this),
        CANONICAL_CORI_SUBSCRIPTION
      );
    }

    _decodeAndSetParams(projectOwner_, nftModule_);

    _initialisePrimaryVesting(nftModule_.vestingData);

    // Load the primary sale modules to the mappings
    for (uint256 i = 0; i < primarySaleModules_.length; ) {
      validPrimaryMarketAddress[primarySaleModules_[i].instanceAddress] = true;
      unchecked {
        i++;
      }
    }

    // Royalty setup
    // If the royalty contract is address(0) then the royalty module
    // has been flagged as not required for this drop.
    // To avoid any possible loss of funds from incorrect configuation we don't
    // set the royalty receiver address to address(0), but rather to the first
    // platform admin
    if (royaltyInfo_.newRoyaltyPaymentSplitterInstance == address(0)) {
      _setDefaultRoyalty(
        projectOwner_,
        royaltyInfo_.royaltyFromSalesInBasisPoints
      );
    } else {
      _setDefaultRoyalty(
        royaltyInfo_.newRoyaltyPaymentSplitterInstance,
        royaltyInfo_.royaltyFromSalesInBasisPoints
      );
    }

    preRevealURI = collectionURIs_[0];
    revealedURI = collectionURIs_[1];

    factory = msg.sender;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                         -->INITIALISE
   * @dev (function) _decodeAndSetParams  Decode NFT Parameters
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param projectOwner_     The project owner
   * ---------------------------------------------------------------------------------------------------------------------
   * @param nftModule_        NFT module data
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function _decodeAndSetParams(
    address projectOwner_,
    NFTModuleConfig calldata nftModule_
  ) internal {
    // Decode the NFT config
    (
      uint256 decodedSupply,
      string memory decodedName,
      string memory decodedSymbol,
      bytes32 decodedPositionProof,
      bool includePriorPhasesInMintTracking,
      bool singleMetadataCollectionFlag,
      uint256 reservedAllocation,
      uint256 assistanceRequestWindow
    ) = abi.decode(
        nftModule_.configData,
        (uint256, string, string, bytes32, bool, bool, uint256, uint256)
      );

    // Initialise values on ERC721M
    _initialiseERC721AM(
      decodedName,
      decodedSymbol,
      decodedSupply,
      includePriorPhasesInMintTracking,
      reservedAllocation
    );

    singleMetadataCollection = singleMetadataCollectionFlag;
    assistanceRequestWindowInSeconds = uint24(assistanceRequestWindow);

    positionProof = decodedPositionProof;

    _transferOwnership(projectOwner_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                          -->LAYERZERO
   * @dev (function) _debitFrom  debit an item from a holder on layerzero call. While off-chain the NFT is custodied in
   * this contract
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param from_               The current owner of the asset
   * ---------------------------------------------------------------------------------------------------------------------
   * @param tokenId_            The tokenId being sent via LayerZero
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function _debitFrom(
    address from_,
    uint16,
    bytes memory,
    uint256 tokenId_
  ) internal virtual override {
    transferFrom(from_, address(this), tokenId_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                          -->LAYERZERO
   * @dev (function) _creditTo  credit an item to a holder on layerzero call. While off-chain the NFT is custodied in
   * this contract, this transfers it back to the holder
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param toAddress_          The recipient of the asset
   * ---------------------------------------------------------------------------------------------------------------------
   * @param tokenId_            The tokenId that has been sent via LayerZero
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function _creditTo(
    uint16,
    address toAddress_,
    uint256 tokenId_
  ) internal virtual override {
    if (!(_exists(tokenId_) && ownerOf(tokenId_) == address(this))) {
      _revert(OwnerQueryForNonexistentToken.selector);
    }

    transferFrom(address(this), toAddress_, tokenId_);
  }

  /** ====================================================================================================================
   *                                            OPERATOR FILTER REGISTRY
   * =====================================================================================================================
   */
  /** ____________________________________________________________________________________________________________________
   *                                                                                                    -->OPERATOR FILTER
   * @dev (function) setApprovalForAll  Operator filter registry override
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param operator            The operator for the approval
   * ---------------------------------------------------------------------------------------------------------------------
   * @param approved            If the operator is approved
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setApprovalForAll(
    address operator,
    bool approved
  ) public override onlyAllowedOperatorApproval(operator) {
    super.setApprovalForAll(operator, approved);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                    -->OPERATOR FILTER
   * @dev (function) approve  Operator filter registry override
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param operator            The operator for the approval
   * ---------------------------------------------------------------------------------------------------------------------
   * @param tokenId             The tokenId for this approval
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function approve(
    address operator,
    uint256 tokenId
  ) public override onlyAllowedOperatorApproval(operator) {
    super.approve(operator, tokenId);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                    -->OPERATOR FILTER
   * @dev (function) transferFrom  Operator filter registry override
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param from                The sender of the token
   * ---------------------------------------------------------------------------------------------------------------------
   * @param to                  The recipient of the token
   * ---------------------------------------------------------------------------------------------------------------------
   * @param tokenId             The tokenId for this approval
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function transferFrom(
    address from,
    address to,
    uint256 tokenId
  ) public override onlyAllowedOperator(from) {
    super.transferFrom(from, to, tokenId);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                    -->OPERATOR FILTER
   * @dev (function) safeTransferFrom  Operator filter registry override
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param from                The sender of the token
   * ---------------------------------------------------------------------------------------------------------------------
   * @param to                  The recipient of the token
   * ---------------------------------------------------------------------------------------------------------------------
   * @param tokenId             The tokenId for this approval
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId
  ) public override onlyAllowedOperator(from) {
    super.safeTransferFrom(from, to, tokenId);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                    -->OPERATOR FILTER
   * @dev (function) safeTransferFrom  Operator filter registry override
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param from                The sender of the token
   * ---------------------------------------------------------------------------------------------------------------------
   * @param to                  The recipient of the token
   * ---------------------------------------------------------------------------------------------------------------------
   * @param tokenId             The tokenId for this approval
   * ---------------------------------------------------------------------------------------------------------------------
   * @param data                bytes data accompanying this transfer operation
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId,
    bytes memory data
  ) public override onlyAllowedOperator(from) {
    super.safeTransferFrom(from, to, tokenId, data);
  }

  /** ====================================================================================================================
   *                                                 PRIVILEGED ACCESS
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                       -->LOCK MINTING
   * @dev (function) setMintingCompleteForeverCannotBeUndone  Allow project owner to set minting complete
   *
   * _____________________________________________________________________________________________________________________
   */
  function setMintingCompleteForeverCannotBeUndone() external onlyOwner {
    mintingComplete = true;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                           -->METADATA
   * @dev (function) lockURIsCannotBeUndone  Lock the URI data for this contract
   *
   * _____________________________________________________________________________________________________________________
   */
  function lockURIsCannotBeUndone() external onlyOwner {
    metadataLocked = true;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                           -->METADATA
   * @dev (function) setURIs  Set the URI data for this contracts
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param uris_[0]   The URI to use pre-reveal
   * ---------------------------------------------------------------------------------------------------------------------
   * @param uris_[1]   The URI for arweave
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setURIs(string[] calldata uris_) public onlyOwner {
    if (metadataLocked) {
      _revert(MetadataIsLocked.selector);
    }

    preRevealURI = uris_[0];
    revealedURI = uris_[1];
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->REVEAL
   * @dev (function) revealCollection  Set the collection to revealed
   *
   * _____________________________________________________________________________________________________________________
   */
  function revealCollection(
    string[] calldata uris_
  ) external payable onlyOwner {
    if (collectionRevealed) {
      _revert(CollectionAlreadyRevealed.selector);
    }
    setURIs(uris_);
    if (singleMetadataCollection) {
      // Open edition, no VRF call
      collectionRevealed = true;
      emit Revealed();
    } else {
      // Standard edition. Reveal will occur in fulfillRandomness
      IDropFactory(factory).requestVRFRandomness{value: msg.value}();
    }
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->REVEAL
   * @dev (function) setPositionProof  Set the metadata position proof
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param positionProof_  The metadata proof
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setPositionProof(bytes32 positionProof_) external onlyOwner {
    positionProof = positionProof_;

    emit PositionProofSet(positionProof_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->ROYALTY
   * @dev (function) setDefaultRoyalty  Set the royalty percentage
   *
   * @notice - we have specifically NOT implemented the ability to have different royalties on a token by token basis.
   * This reduces the complexity of processing on multi-buys, and also avoids challenges to decentralisation (e.g. the
   * project targetting one users tokens with larger royalties)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param recipient_   Royalty receiver
   * ---------------------------------------------------------------------------------------------------------------------
   * @param fraction_   Royalty fraction
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setDefaultRoyalty(
    address recipient_,
    uint96 fraction_
  ) public onlyOwner {
    _setDefaultRoyalty(recipient_, fraction_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->ROYALTY
   * @dev (function) deleteDefaultRoyalty  Delete the royalty percentage claimed
   *
   * _____________________________________________________________________________________________________________________
   */
  function deleteDefaultRoyalty() public onlyOwner {
    _deleteDefaultRoyalty();
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->SUPPORT
   * @dev (function) requestAssistance  Request assistance. Submitting this transaction unlocks the platform admin
   *                                    functions on the sales modules associated with this NFT. Note, the platform admin
   *                                    has no privilidged access to this NFT, but there are admin methods on the sale
   *                                    modules that they can call IF you provide authorisation by calling this method.
   *
   *                                    This authorisation automatically expires after the support window period
   *                                    (assistanceRequestWindowInSeconds), which is set when this contract is initialised
   *                                    and cannot be changed.
   *
   *                                    Only call this method if you require support from the platform admin and
   *                                    understand what this entails. You must provide a text reason as to your request
   *                                    for support. This reason is emitted on an event from this method
   * _____________________________________________________________________________________________________________________
   */
  function requestAssistance(string memory supportReason_) public onlyOwner {
    assistanceRequestTimeStamp = uint32(block.timestamp);
    emit SupportRequested(supportReason_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->SUPPORT
   * @dev (function) assistanceWindowOpen  Returns if the owner of this contract has requested admin assistance using the
   *                                       requestAssistance onlyOwner method on this contract. This value is read by
   *                                       sales modules associated with this NFT to determine if admin support actions
   *                                       can be taken. If the admin support window is not open admin support calls to
   *                                       sale modules cannot be made.
   * _____________________________________________________________________________________________________________________
   */
  function assistanceWindowOpen()
    external
    view
    returns (bool adminAssistanceWindowOpen_)
  {
    return
      block.timestamp <=
      assistanceRequestTimeStamp + assistanceRequestWindowInSeconds;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->REVEAL
   * @dev (function) fulfillRandomWords  Callback from the VRF oracle (on factory) with randomness
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param requestId_      The Id of this request (this contract will submit a single request)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param randomWords_   The random words returned from chainlink
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function fulfillRandomWords(
    uint256 requestId_,
    uint256[] memory randomWords_
  ) external {
    if (msg.sender == factory && !collectionRevealed) {
      unchecked {
        vrfStartPosition = (randomWords_[0] % maxSupply);
      }
      collectionRevealed = true;
      emit RandomNumberReceived(requestId_, randomWords_[0]);
      emit VRFPositionSet(vrfStartPosition);
      emit Revealed();
    } else {
      _revert(MetadropFactoryOnlyOncePerReveal.selector);
    }
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->FINANCE
   * @dev (function) fallback  Explicitly revert on fallback()
   *
   * _____________________________________________________________________________________________________________________
   */
  fallback() external payable {
    revert();
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) receive   Reject eth of unkown source
   * _____________________________________________________________________________________________________________________
   */
  receive() external payable onlyOwner {}

  /** ====================================================================================================================
   *                                             COLLECTION INFORMATION GETTERS
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) metadropCustom  Returns if this contract is a custom NFT (true) or is a standard metadrop
   *                                 ERC721M (false)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return isMetadropCustom_   The total minted supply of this collection
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function metadropCustom() external pure returns (bool isMetadropCustom_) {
    return (false);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) totalSupply  Returns total supply (minted - burned)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return totalSupply_   The total supply of this collection (minted - burned)
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function totalSupply()
    public
    view
    override(ERC721AM, INFTByMetadrop)
    returns (uint256 totalSupply_)
  {
    return super.totalSupply();
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) totalUnminted  Returns the remaining unminted supply
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return totalUnminted_   The total unminted supply of this collection
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function totalUnminted() public view returns (uint256 totalUnminted_) {
    return maxSupply - _totalMinted();
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) totalMinted  Returns the total number of tokens ever minted
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return totalMinted_   The total minted supply of this collection
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function totalMinted() public view returns (uint256 totalMinted_) {
    return _totalMinted();
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) totalBurned  Returns the count of tokens sent to the burn address
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return totalBurned_   The total burned supply of this collection
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function totalBurned() public view returns (uint256 totalBurned_) {
    return _totalBurned();
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) phaseMintCount  Number of tokens minted for the queried phase
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return phaseQuantityMinted_   The total minting for this phase
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function phaseMintCount(
    uint256 index_
  ) external view returns (uint256 phaseQuantityMinted_) {
    return currentIndexes[index_];
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) tokenURI  Returns the URI for the passed token
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return tokenURI_   The token URI
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function tokenURI(
    uint256 tokenId
  ) public view virtual override returns (string memory tokenURI_) {
    if (!_exists(tokenId)) _revert(URIQueryForNonexistentToken.selector);

    unchecked {
      if (!collectionRevealed) {
        return preRevealURI;
      } else {
        if (singleMetadataCollection) {
          // single metadata collection, just return the revealed URI:
          return revealedURI;
        } else {
          // Standard edition, append the tokenId:
          return
            string.concat(
              revealedURI,
              ((tokenId + vrfStartPosition) % maxSupply).toString(),
              ".json"
            );
        }
      }
    }
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) supportsInterface   Override is required by Solidity.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return bool    If the interface is supported
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual override(ERC721AM, ERC2981, EPS4907) returns (bool) {
    // Supports the following `interfaceId`s:
    // - IERC165: 0x01ffc9a7
    // - IERC721: 0x80ac58cd
    // - IERC721Metadata: 0x5b5e139f
    // - IERC2981: 0x2a55205a
    // - IERC4907: 0xad092b5c
    // - IEPS4907: 0xd50ef07c
    // - IONFT721Core: 0x7bb0080b
    return
      ERC721AM.supportsInterface(interfaceId) ||
      ERC2981.supportsInterface(interfaceId) ||
      EPS4907.supportsInterface(interfaceId) ||
      interfaceId == 0x7bb0080b; // IONFT721Core
  }

  /** ====================================================================================================================
   *                                                    MINTING
   * =====================================================================================================================
   */
  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) metadropMint  Mint tokens. Can only be called from a valid primary market contract
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param caller_                The address that has called mint through the primary sale module.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param recipient_             The address that will receive new assets.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param allowanceAddress_      The address that has an allowance being used in this mint. This will be the same as the
   *                               calling address in almost all cases. An example of when they may differ is in a list
   *                               mint where the caller is a delegate of another address with an allowance in the list.
   *                               The caller is performing the mint, but it is the allowance for the allowance address
   *                               that is being checked and decremented in this mint.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param quantityToMint_        The quantity of tokens to be minted
   * ---------------------------------------------------------------------------------------------------------------------
   * @param unitPrice_             The unit price for each token
   * ---------------------------------------------------------------------------------------------------------------------
   * @param phaseId_               The ID of this phase
   * ---------------------------------------------------------------------------------------------------------------------
   * @param phaseMintLimit_        The max limit for this phase
   * ---------------------------------------------------------------------------------------------------------------------
   * @param reservedAllocationPhase_    If the calling phase draws from a reserved allocation
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function metadropMint(
    address caller_,
    address recipient_,
    address allowanceAddress_,
    uint256 quantityToMint_,
    uint256 unitPrice_,
    uint256 phaseId_,
    uint256 phaseMintLimit_,
    bool reservedAllocationPhase_
  ) external payable {
    if (mintingComplete) {
      _revert(MintingIsClosedForever.selector);
    }

    if (!validPrimaryMarketAddress[msg.sender])
      _revert(InvalidAddress.selector);

    uint256[] memory tokenIds = _mint(
      recipient_,
      quantityToMint_,
      phaseId_,
      phaseMintLimit_,
      reservedAllocationPhase_
    );

    emit MetadropMint(
      allowanceAddress_,
      recipient_,
      caller_,
      msg.sender,
      unitPrice_,
      tokenIds
    );
  }
  /** ====================================================================================================================
   */
}

