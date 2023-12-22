// SPDX-License-Identifier: MIT
// Metadrop Contracts (v2.1.0)

pragma solidity 0.8.19;

import {IERC20} from "./IERC20.sol";
import {IConfigStructures} from "./IConfigStructures.sol";
import {IErrors} from "./IErrors.sol";

interface IDropFactory is IConfigStructures, IErrors {
  /** ====================================================================================================================
   *                                                     EVENTS
   * =====================================================================================================================
   */

  event DefaultMetadropPrimaryShareBasisPointsSet(
    uint256 defaultPrimaryFeeBasisPoints
  );
  event DefaultMetadropRoyaltyBasisPointsSet(
    uint256 defaultMetadropRoyaltyBasisPoints
  );
  event PrimaryFeeOverrideByDropSet(string dropId, uint256 percentage);
  event RoyaltyBasisPointsOverrideByDropSet(
    string dropId,
    uint256 royaltyBasisPoints
  );
  event PlatformTreasurySet(address platformTreasury);
  event TemplateAdded(
    TemplateStatus status,
    uint256 templateNumber,
    uint256 loadedDate,
    address templateAddress,
    string templateDescription
  );
  event TemplateUpdated(
    uint256 templateNumber,
    address oldTemplateAddress,
    address newTemplateAddress
  );
  event TemplateTerminated(uint16 templateNumber);

  event PauseCutOffInDaysSet(uint16 cutOffInDays);
  event SubmissionFeeUpdated(uint256 oldFee, uint256 newFee);
  event DropDeployed(
    string dropId,
    address nftInstance,
    PrimarySaleModuleInstance[],
    address royaltySplitterInstance
  );
  event VRFModeSet(uint8 mode);
  event VRFSubscriptionIdSet(uint64 vrfSubscriptionId_);
  event VRFKeyHashSet(bytes32 vrfKeyHash);
  event VRFCallbackGasLimitSet(uint32 vrfCallbackGasLimit);
  event VRFRequestConfirmationsSet(uint16 vrfRequestConfirmations);
  event VRFNumWordsSet(uint32 vrfNumWords);
  event MetadropOracleAddressSet(address metadropOracleAddress);
  event MessageValidityInSecondsSet(uint256 messageValidityInSeconds);
  event ModuleETHBalancesTransferred(address[] modules);
  event ModuleERC20BalancesTransferred(
    address[] modules,
    address erc20Contract
  );
  event ModulePhaseTimesUpdated(
    address[] modules,
    uint256[] startTimes,
    uint256[] endTimes
  );
  event ModulePhaseMaxSupplysUpdated(address[] modules, uint256[] maxSupplys);
  event ModuleOracleAddressUpdated(address[] modules, address oracle);
  event ModuleAntiSybilOff(address[] modules);
  event ModuleEPSOff(address[] modules);
  event ModuleEPSOn(address[] modules);
  event ModulePublicMintPricesUpdated(
    address[] modules,
    uint256[] publicMintPrice
  );
  event ModuleMerkleRootsUpdated(address[] modules, bytes32[] merkleRoot);
  event AuxCallSucceeded(
    address[] modules,
    uint256 value,
    bytes data,
    uint256 txGas
  );
  event PreviousRootValidityPeriodSet(uint32 validityInSeconds);

  /** ====================================================================================================================
   *                                                    FUNCTIONS
   * =====================================================================================================================
   */

  /** ====================================================================================================================
   *                                                      GETTERS
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) getPlatformTreasury  return the treasury address (provided as explicit method rather than public var)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return platformTreasury_  Treasury address
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function getPlatformTreasury()
    external
    view
    returns (address platformTreasury_);

  /** ====================================================================================================================
   *                                                 PRIVILEGED ACCESS
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) setVRFMode    Set VRF source to chainlink (0) or arrng (1)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfMode_    The VRF mode.

   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setVRFMode(uint8 vrfMode_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) setVRFSubscriptionId    Set the chainlink subscription id..
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfSubscriptionId_    The VRF subscription that this contract will consume chainlink from.

   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setVRFSubscriptionId(uint64 vrfSubscriptionId_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) setVRFKeyHash   Set the chainlink keyhash (gas lane).
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfKeyHash_  The desired VRF keyhash
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setVRFKeyHash(bytes32 vrfKeyHash_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) setVRFCallbackGasLimit  Set the chainlink callback gas limit
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfCallbackGasLimit_  Callback gas limit
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setVRFCallbackGasLimit(uint32 vrfCallbackGasLimit_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) setVRFRequestConfirmations  Set the chainlink number of confirmations required
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfRequestConfirmations_  Required number of confirmations
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setVRFRequestConfirmations(uint16 vrfRequestConfirmations_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) setVRFNumWords  Set the chainlink number of words required
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfNumWords_  Required number of confirmations
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setVRFNumWords(uint32 vrfNumWords_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->ORACLE
   * @dev (function) setMetadropOracleAddress  Set the metadrop trusted oracle address
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param metadropOracleAddress_   Trusted metadrop oracle address
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setMetadropOracleAddress(address metadropOracleAddress_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->ORACLE
   * @dev (function) setMessageValidityInSeconds  Set the validity period of signed messages
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageValidityInSeconds_   Validity period in seconds for messages signed by the trusted oracle
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setMessageValidityInSeconds(
    uint256 messageValidityInSeconds_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                           -->PAUSABLE
   * @dev (function) setPauseCutOffInDays    Set the number of days from the start date that a contract can be paused for
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param pauseCutOffInDays_    Default pause cutoff in days
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setPauseCutOffInDays(uint16 pauseCutOffInDays_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->FINANCE
   * @dev (function) setDropFee    Set drop fee (if any)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param fee_    New drop fee
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setDropFee(uint256 fee_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->FINANCE
   * @dev (function) setPlatformTreasury    Set the platform treasury address
   *
   * Set the address that platform fees will be paid to / can be withdrawn to.
   * Note that this is restricted to the highest authority level, the super
   * admin. Platform admins can trigger a withdrawal to the treasury, but only
   * the default admin can set or alter the treasury address. It is recommended
   * that the default admin is highly secured and restrited e.g. a multi-sig.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param platformTreasury_    New treasury address
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setPlatformTreasury(address platformTreasury_) external;

  /** ====================================================================================================================
   *                                                  MODULE MAINTENANCE
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) withdrawETHFromModules   A withdraw function to allow ETH to be withdrawn from n modules to the
   *                                          treasury address set on the factory (this contract)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function withdrawETHFromModules(address[] calldata moduleAddresses_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) withdrawERC20FromModules   A withdraw function to allow ERC20s to be withdrawn from n modules to the
   *                                            treasury address set on the modules
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param tokenContract_         The token contract for withdrawal
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function withdrawERC20FromModules(
    address[] calldata moduleAddresses_,
    address tokenContract_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) updatePhaseTimesOnModules   Update the phase start and/or end on the provided module(s). Note that
   *                                             sending a 0 means you are NOT updating that time.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * @param startTimes_            An array of start times
   * ---------------------------------------------------------------------------------------------------------------------
   * @param endTimes_              An array of end times
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updatePhaseTimesOnModules(
    address[] calldata moduleAddresses_,
    uint256[] calldata startTimes_,
    uint256[] calldata endTimes_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) updatePhaseMaxSupplyOnModules   Update the phase max supply on the provided module(s)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * @param maxSupplys_            An array of max supply integers
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updatePhaseMaxSupplyOnModules(
    address[] calldata moduleAddresses_,
    uint256[] calldata maxSupplys_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) updateMetadropOracleAddressOnModules   Allow platform admin to update trusted oracle address
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_        An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * @param metadropOracleAddress_  The new metadrop oracle address
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updateMetadropOracleAddressOnModules(
    address[] calldata moduleAddresses_,
    address metadropOracleAddress_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) updateAntiSybilOffOnModules     Allow platform admin to turn off anti-sybil protection on modules
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updateAntiSybilOffOnModules(
    address[] calldata moduleAddresses_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) updateEPSOffOnModules     Allow platform admin to turn off EPS on modules
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updateEPSOffOnModules(address[] calldata moduleAddresses_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) updateEPSOnOnModules     Allow platform admin to turn on EPS on modules
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updateEPSOnOnModules(address[] calldata moduleAddresses_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->MODULES
   * @dev (function) updatePublicMintPriceOnModules  Update the price per NFT for the specified drops
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_        An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * @param newPublicMintPrices_    An array of the new price per mint
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updatePublicMintPriceOnModules(
    address[] calldata moduleAddresses_,
    uint256[] calldata newPublicMintPrices_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->MODULES
   * @dev (function) updateMerkleRootsOnModules  Set the merkleroot on the specified modules
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * @param merkleRoots_           An array of the bytes32 merkle roots to set
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updateMerkleRootsOnModules(
    address[] calldata moduleAddresses_,
    bytes32[] calldata merkleRoots_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) pauseDeployedContract   Call pause on deployed contracts
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function pauseDeployedContract(address[] calldata moduleAddresses_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) unpauseDeployedContract   Call unpause on deployed contracts
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function unpauseDeployedContract(
    address[] calldata moduleAddresses_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->AUCTION
   * @dev (function) updateAuctionFinalFloorDetails   set final auction floor details
   *
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param module_                                      An single module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * @param endAuctionFloorPrice_                        The floor price at the end of the auction
   * ---------------------------------------------------------------------------------------------------------------------
   * @param endAuctionAboveFloorBidQuantity_             Items above the floor price
   * ---------------------------------------------------------------------------------------------------------------------
   * @param endAuctionLastFloorPosition_                 The last floor position for the auction
   * ---------------------------------------------------------------------------------------------------------------------
   * @param endAuctionRunningTotalAtLastFloorPosition_   Running total at the last floor position
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updateAuctionFinalFloorDetails(
    address module_,
    uint80 endAuctionFloorPrice_,
    uint56 endAuctionAboveFloorBidQuantity_,
    uint56 endAuctionLastFloorPosition_,
    uint56 endAuctionRunningTotalAtLastFloorPosition_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) auxCall      Make a previously undefined external call
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * @param value_                 The value for the auxilliary call
   * ---------------------------------------------------------------------------------------------------------------------
   * @param data_                  The data for the auxilliary call
   * ---------------------------------------------------------------------------------------------------------------------
   * @param txGas_                 The gas for the auxilliary call
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function auxCall(
    address[] calldata moduleAddresses_,
    uint256 value_,
    bytes memory data_,
    uint256 txGas_
  ) external returns (bool success);

  /** ====================================================================================================================
   *                                                 FACTORY BALANCES
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->FINANCE
   * @dev (function) withdrawETH   A withdraw function to allow ETH to be withdrawn to the treasury
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param amount_  The amount to withdraw
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function withdrawETH(uint256 amount_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->FINANCE
   * @dev (function) withdrawERC20   A withdraw function to allow ERC20s to be withdrawn to the treasury
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param token_   The contract address of the token being withdrawn
   * ---------------------------------------------------------------------------------------------------------------------
   * @param amount_  The amount to withdraw
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function withdrawERC20(IERC20 token_, uint256 amount_) external;

  /** ====================================================================================================================
   *                                                    VRF SERVER
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) requestVRFRandomness  Get the metadata start position for use on reveal of the calling collection
   * _____________________________________________________________________________________________________________________
   */
  function requestVRFRandomness() external payable;

  /** ====================================================================================================================
   *                                                    TEMPLATES
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                          -->TEMPLATES
   * @dev (function) addTemplate  Add a contract to the template library
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param contractAddress_              The address of the deployed contract that will be a template
   * ---------------------------------------------------------------------------------------------------------------------
   * @param templateDescription_          The description of the template
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function addTemplate(
    address payable contractAddress_,
    string calldata templateDescription_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                          -->TEMPLATES
   * @dev (function) updateTemplate  Update an existing contract in the template library
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param templateId_                   The Id of the existing template that we are updating
   * ---------------------------------------------------------------------------------------------------------------------
   * @param contractAddress_              The address of the deployed contract that will be the new template
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updateTemplate(
    uint256 templateId_,
    address payable contractAddress_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                          -->TEMPLATES
   * @dev (function) terminateTemplate  Mark a template as terminated
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param templateNumber_              The number of the template to be marked as terminated
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function terminateTemplate(uint16 templateNumber_) external;

  /** ====================================================================================================================
   *                                                    DROP CREATION
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->DROPS
   * @dev (function) createDrop     Create a drop using the stored and approved configuration if called by the address
   *                                that the user has designated as project admin
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param dropId_                        The drop Id being approved
   * ---------------------------------------------------------------------------------------------------------------------
   * @param nftModule_                     Struct containing the relevant config for the NFT module
   * ---------------------------------------------------------------------------------------------------------------------
   * @param primarySaleModulesConfig_      Array of structs containing the config details for all primary sale modules
   *                                       associated with this drop (can be 1 to n)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param royaltyPaymentSplitterModule_  Struct containing the relevant config for the royalty splitter module
   * ---------------------------------------------------------------------------------------------------------------------
   * @param salesPageHash_                 A hash of sale page data
   * ---------------------------------------------------------------------------------------------------------------------
   * @param customNftAddress_              If this drop uses a custom NFT this will hold that contract's address
   * ---------------------------------------------------------------------------------------------------------------------
   * @param collectionURIs_                An array of collection URIs (pre-reveal, ipfs and arweave)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param signedMessage_                 The signed message object
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function createDrop(
    string calldata dropId_,
    NFTModuleConfig calldata nftModule_,
    PrimarySaleModuleConfig[] calldata primarySaleModulesConfig_,
    RoyaltySplitterModuleConfig calldata royaltyPaymentSplitterModule_,
    bytes32 salesPageHash_,
    address customNftAddress_,
    string[2] calldata collectionURIs_,
    SignedDropMessageDetails calldata signedMessage_
  ) external payable;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->DROPS
   * @dev (function) configHashMatches  Check the passed config against the stored config hash
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param dropId_                        The drop Id being approved
   * ---------------------------------------------------------------------------------------------------------------------
   * @param nftModule_                     Struct containing the relevant config for the NFT module
   * ---------------------------------------------------------------------------------------------------------------------
   * @param primarySaleModulesConfig_      Array of structs containing the config details for all primary sale modules
   *                                       associated with this drop (can be 1 to n)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param royaltyPaymentSplitterModule_  Struct containing the relevant config for the royalty splitter module
   * ---------------------------------------------------------------------------------------------------------------------
   * @param salesPageHash_                 A hash of sale page data
   * ---------------------------------------------------------------------------------------------------------------------
   * @param customNftAddress_              If this drop uses a custom NFT this will hold that contract's address
   * ---------------------------------------------------------------------------------------------------------------------
   * @param signedMessage_                 The signed message object
   * ---------------------------------------------------------------------------------------------------------------------
   * @return matches_                      Whether the hash matches (true) or not (false)
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function configHashMatches(
    string calldata dropId_,
    NFTModuleConfig calldata nftModule_,
    PrimarySaleModuleConfig[] calldata primarySaleModulesConfig_,
    RoyaltySplitterModuleConfig calldata royaltyPaymentSplitterModule_,
    bytes32 salesPageHash_,
    address customNftAddress_,
    SignedDropMessageDetails calldata signedMessage_
  ) external view returns (bool matches_);

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->DROPS
   * @dev (function) createConfigHash  Create the config hash
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param dropId_                        The drop Id being approved
   * ---------------------------------------------------------------------------------------------------------------------
   * @param nftModule_                     Struct containing the relevant config for the NFT module
   * ---------------------------------------------------------------------------------------------------------------------
   * @param primarySaleModulesConfig_      Array of structs containing the config details for all primary sale modules
   *                                       associated with this drop (can be 1 to n)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param royaltyPaymentSplitterModule_  Struct containing the relevant config for the royalty splitter module
   * ---------------------------------------------------------------------------------------------------------------------
   * @param salesPageHash_                 A hash of sale page data
   * ---------------------------------------------------------------------------------------------------------------------
   * @param customNftAddress_              If this drop uses a custom NFT this will hold that contract's address
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageTimeStamp_              When the message for this config hash was signed
   * ---------------------------------------------------------------------------------------------------------------------
   * @return configHash_                   The bytes32 config hash
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function createConfigHash(
    string calldata dropId_,
    NFTModuleConfig calldata nftModule_,
    PrimarySaleModuleConfig[] calldata primarySaleModulesConfig_,
    RoyaltySplitterModuleConfig calldata royaltyPaymentSplitterModule_,
    bytes32 salesPageHash_,
    address customNftAddress_,
    uint256 messageTimeStamp_
  ) external pure returns (bytes32 configHash_);
}

