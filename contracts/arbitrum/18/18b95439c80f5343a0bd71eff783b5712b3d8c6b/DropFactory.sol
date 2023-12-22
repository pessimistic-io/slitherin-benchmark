// SPDX-License-Identifier: BUSL 1.0
// Metadrop Contracts (v2.0.0)

/**
 *
 * @title DropFactory.sol - Core contract for metadrop NFT drop creation.
 *
 * @author metadrop https://metadrop.com/
 *
 * @notice This contract performs the following roles:
 * - Storage of drop data that has been submitted to metadrop for approval.
 *   This information is held in hash format, and compared with sent data
 *   to create the drop.
 * - Drop creation. This factory will create the required NFT contracts for
 *   an approved drop using the approved confirmation.
 * - Platform Utilities. This contract holds core platform data accessed by other
 *   on-chain elements of the metadrop ecosystem. For example, VRF functionality.
 *
 */

pragma solidity 0.8.19;

import {Address} from "./Address.sol";
import {Clones} from "./Clones.sol";
import {VRFCoordinatorV2Interface} from "./VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "./VRFConsumerBaseV2.sol";
import {ArrngConsumer} from "./ArrngConsumer.sol";
import {IDropFactory} from "./IDropFactory.sol";
import {Ownable} from "./Ownable.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {INFTByMetadrop} from "./INFTByMetadrop.sol";
import {IPrimarySaleModule} from "./IPrimarySaleModule.sol";
import {IPrimaryVestingByMetadrop} from "./IPrimaryVestingByMetadrop.sol";
import {IPublicMintByMetadrop} from "./IPublicMintByMetadrop.sol";
import {IListMintByMetadrop} from "./IListMintByMetadrop.sol";
import {IAuctionByMetadrop} from "./IAuctionByMetadrop.sol";
import {IRoyaltyPaymentSplitterByMetadrop} from "./IRoyaltyPaymentSplitterByMetadrop.sol";
import {AuthorityModel} from "./AuthorityModel.sol";
import {IPausable} from "./IPausable.sol";

/**
 *
 * @dev Inheritance details:
 *      IDropFactory            Interface definition for the metadrop drop factory
 *      Ownable                 OZ ownable implementation - provided for backwards compatibility
 *                              with any infra that assumes a project owner.
 *      AccessControl           OZ access control implementation - used for authority control
 *      VRFConsumerBaseV2       This contract will call chainlink VRF on behalf of deployed NFT
 *                              contracts, relaying the returned result to the NFT contract
 *
 */

contract DropFactory is
  IDropFactory,
  Ownable,
  AuthorityModel,
  VRFConsumerBaseV2,
  ArrngConsumer
{
  using Address for address;
  using Clones for address payable;
  using SafeERC20 for IERC20;

  uint16 public constant MAX_REQUEST_CONFIRMATIONS = 200;
  uint32 public constant MAX_NUM_WORDS = 500;

  // The number of days that must have passed before the details for a drop held on chain can be deleted.
  uint32 public dropExpiryInDays;

  // Pause should not be allowed indefinitely
  uint8 public pauseCutOffInDays;

  // VRF mode
  // 0 = chainlink
  // 1 = aarng
  uint8 public vrfMode;

  // Address for all platform fee payments
  address private platformTreasury;

  // Metadrop trusted oracle address
  address public metadropOracleAddress;

  // Fee for drop submission (default is zero)
  uint256 public dropFeeETH;

  // The oracle signed message validity period:
  uint256 public messageValidityInMinutes = 15;

  // Chainlink config
  VRFCoordinatorV2Interface public immutable vrfCoordinatorInterface;
  uint64 public vrfSubscriptionId;
  bytes32 public vrfKeyHash;
  uint32 public vrfCallbackGasLimit;
  uint16 public vrfRequestConfirmations;
  uint32 public vrfNumWords;

  // Array of templates:
  // Note that this means that templates can be updated as the metadrop NFT evolves.
  // Using a new one will mean that all drops from that point forward will use the new contract template.
  // All deployed NFT contracts are NOT upgradeable and will continue to use the contract as deployed
  // At the time of drop.

  Template[] public contractTemplates;

  // Map the dropId to the Drop object
  //   struct DropApproval {
  //   DropStatus status;
  //   uint32 lastChangedDate;
  //   address dropOwnerAddress;
  //   bytes32 configHash;
  // }
  mapping(string => DropApproval) private dropDetailsByDropId;

  // Map to store deployed NFT addresses:
  mapping(address => bool) public deployedNFTContracts;

  // Mappings to store VRF request IDs:
  mapping(uint256 => address) public addressForChainlinkVRFRequestId;
  mapping(uint256 => address) public addressForArrngVRFRequestId;

  /** ====================================================================================================================
   *                                                    CONSTRUCTOR
   * =====================================================================================================================

  /** ____________________________________________________________________________________________________________________
   *                                                                                                        -->CONSTRUCTOR
   * @dev constructor           The constructor is not called when the contract is cloned. In this
   *                            constructor we just setup default values and set the template contract to initialised.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param superAdmin_                                     The address that can add and remove user authority roles. Will
   *                                                        also be added as the first platform admin.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param platformAdmins_                                 The address(es) for the platform admin(s)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param reviewAdmins_                                   The address(es) for the review admin(s)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param platformTreasury_                               The address of the platform treasury. This will be used on
   *                                                        primary vesting for the platform share of funds and on the
   *                                                        royalty payment splitter for the platform share.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfCoordinator_                                 The address of the VRF coordinator
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfKeyHash_             The VRF key hash to determine the gas channel to use for VRF calls (i.e. the max gas
   *                                you are willing to supply on the VRF call)
   *                                - Mainnet 200 gwei: 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef
   *                                - Goerli 150 gwei 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfSubscriptionId_      The subscription ID that chainlink tokens are consumed from for VRF calls
   * ---------------------------------------------------------------------------------------------------------------------
   * @param metadropOracleAddress_  The address of the metadrop oracle signer
   * ---------------------------------------------------------------------------------------------------------------------
   * @param initialTemplateAddresses_     An array of intiial template addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * @param initialTemplateDescriptions_  An array of initial template descriptions
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  constructor(
    address superAdmin_,
    address[] memory platformAdmins_,
    address[] memory reviewAdmins_,
    address platformTreasury_,
    address vrfCoordinator_,
    bytes32 vrfKeyHash_,
    uint64 vrfSubscriptionId_,
    address metadropOracleAddress_,
    address payable[] memory initialTemplateAddresses_,
    string[] memory initialTemplateDescriptions_
  ) VRFConsumerBaseV2(vrfCoordinator_) {
    // The initial instance owner is set as the Ownable owner on all cloned contracts:
    if (superAdmin_ == address(0)) {
      _revert(SuperAdminCannotBeAddressZero.selector);
    }

    // superAdmin can grant and revoke all other roles. This address MUST be secured.
    // For the duration of this constructor only the super admin is the deployer.
    // This is so the deployer can set initial authorities.
    // We set to the configured super admin address at the end of the constructor.
    superAdmin = _msgSender();
    // Grant platform admin to the deployer for the duration of the constructor:
    grantPlatformAdmin(_msgSender());

    grantPlatformAdmin(superAdmin_);
    grantReviewAdmin(superAdmin_);

    for (uint256 i = 0; i < platformAdmins_.length; i++) {
      grantPlatformAdmin(platformAdmins_[i]);
    }

    for (uint256 i = 0; i < reviewAdmins_.length; i++) {
      grantReviewAdmin(reviewAdmins_[i]);
    }

    // Set platform treasury:
    if (platformTreasury_ == address(0)) {
      _revert(PlatformTreasuryCannotBeAddressZero.selector);
    }
    platformTreasury = platformTreasury_;

    // Set default chainlink VRF details
    if (vrfCoordinator_ == address(0)) {
      _revert(VRFCoordinatorCannotBeAddressZero.selector);
    }
    vrfCoordinatorInterface = VRFCoordinatorV2Interface(vrfCoordinator_);
    vrfKeyHash = vrfKeyHash_;
    vrfSubscriptionId = vrfSubscriptionId_;
    vrfCallbackGasLimit = 150000;
    vrfRequestConfirmations = 3;
    vrfNumWords = 1;

    pauseCutOffInDays = 90;

    if (metadropOracleAddress_ == address(0)) {
      _revert(MetadropOracleCannotBeAddressZero.selector);
    }
    metadropOracleAddress = metadropOracleAddress_;

    _loadInitialTemplates(
      initialTemplateAddresses_,
      initialTemplateDescriptions_
    );

    // Revoke platform admin status of the deployer and transfer superAdmin
    // and ownable owner to the superAdmin_:
    revokePlatformAdmin(_msgSender());
    transferSuperAdmin(superAdmin_);
    _transferOwnership(superAdmin_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                         -->INITIALISE
   * @dev (function) _loadInitialTemplates  Load initial templates as part of the constructor
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param initialTemplateAddresses_     An array of template addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * @param initialTemplateDescriptions_  An array of template descriptions
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function _loadInitialTemplates(
    address payable[] memory initialTemplateAddresses_,
    string[] memory initialTemplateDescriptions_
  ) internal {
    if (
      initialTemplateAddresses_.length != initialTemplateDescriptions_.length
    ) {
      _revert(ListLengthMismatch.selector);
    }

    for (uint256 i = 0; i < initialTemplateAddresses_.length; i++) {
      addTemplate(
        initialTemplateAddresses_[i],
        initialTemplateDescriptions_[i]
      );
    }
  }

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
    returns (address platformTreasury_)
  {
    return (platformTreasury);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) getDropDetails   Getter for the drop details held on chain
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param dropId_  The drop ID being queries
   * ---------------------------------------------------------------------------------------------------------------------
   * @return dropDetails_  The drop details struct for the provided drop Id.
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function getDropDetails(
    string calldata dropId_
  ) external view returns (DropApproval memory dropDetails_) {
    return (dropDetailsByDropId[dropId_]);
  }

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
  function setVRFMode(uint8 vrfMode_) public onlyPlatformAdmin {
    if (vrfMode_ > 1) {
      _revert(UnrecognisedVRFMode.selector);
    }
    vrfMode = vrfMode_;
    emit VRFModeSet(vrfMode_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) setVRFSubscriptionId    Set the chainlink subscription id..
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfSubscriptionId_    The VRF subscription that this contract will consume chainlink from.

   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setVRFSubscriptionId(
    uint64 vrfSubscriptionId_
  ) public onlyPlatformAdmin {
    vrfSubscriptionId = vrfSubscriptionId_;
    emit VRFSubscriptionIdSet(vrfSubscriptionId_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) setVRFKeyHash   Set the chainlink keyhash (gas lane).
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfKeyHash_  The desired VRF keyhash
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setVRFKeyHash(bytes32 vrfKeyHash_) external onlyPlatformAdmin {
    vrfKeyHash = vrfKeyHash_;
    emit VRFKeyHashSet(vrfKeyHash_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) setVRFCallbackGasLimit  Set the chainlink callback gas limit
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfCallbackGasLimit_  Callback gas limit
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setVRFCallbackGasLimit(
    uint32 vrfCallbackGasLimit_
  ) external onlyPlatformAdmin {
    vrfCallbackGasLimit = vrfCallbackGasLimit_;
    emit VRFCallbackGasLimitSet(vrfCallbackGasLimit_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) setVRFRequestConfirmations  Set the chainlink number of confirmations required
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfRequestConfirmations_  Required number of confirmations
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setVRFRequestConfirmations(
    uint16 vrfRequestConfirmations_
  ) external onlyPlatformAdmin {
    if (vrfRequestConfirmations_ > MAX_REQUEST_CONFIRMATIONS) {
      _revert(ValueExceedsMaximum.selector);
    }
    vrfRequestConfirmations = vrfRequestConfirmations_;
    emit VRFRequestConfirmationsSet(vrfRequestConfirmations_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) setVRFNumWords  Set the chainlink number of words required
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vrfNumWords_  Required number of confirmations
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setVRFNumWords(uint32 vrfNumWords_) external onlyPlatformAdmin {
    if (vrfNumWords_ > MAX_NUM_WORDS) {
      _revert(ValueExceedsMaximum.selector);
    }
    vrfNumWords = vrfNumWords_;
    emit VRFNumWordsSet(vrfNumWords_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->ORACLE
   * @dev (function) setMetadropOracleAddress  Set the metadrop trusted oracle address
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param metadropOracleAddress_   Trusted metadrop oracle address
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setMetadropOracleAddress(
    address metadropOracleAddress_
  ) external onlyPlatformAdmin {
    if (metadropOracleAddress_ == address(0)) {
      _revert(MetadropOracleCannotBeAddressZero.selector);
    }
    metadropOracleAddress = metadropOracleAddress_;
    emit MetadropOracleAddressSet(metadropOracleAddress_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->ORACLE
   * @dev (function) setMessageValidityInMinutes  Set the validity period of signed messages
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageValidityInMinutes_   Validity period in seconds for messages signed by the trusted oracle
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setMessageValidityInMinutes(
    uint256 messageValidityInMinutes_
  ) external onlyPlatformAdmin {
    messageValidityInMinutes = messageValidityInMinutes_;
    emit MessageValidityInMinutesSet(messageValidityInMinutes_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                           -->PAUSABLE
   * @dev (function) setPauseCutOffInDays    Set the number of days from the start date that a contract can be paused for
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param pauseCutOffInDays_    Default pause cutoff in days
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setPauseCutOffInDays(
    uint8 pauseCutOffInDays_
  ) external onlyPlatformAdmin {
    pauseCutOffInDays = pauseCutOffInDays_;

    emit PauseCutOffInDaysSet(pauseCutOffInDays_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->FINANCE
   * @dev (function) setDropFeeETH    Set drop fee (if any)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param fee_    New drop fee
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setDropFeeETH(uint256 fee_) external onlyPlatformAdmin {
    uint256 oldDropFee = dropFeeETH;
    dropFeeETH = fee_;
    emit SubmissionFeeETHUpdated(oldDropFee, fee_);
  }

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
  function setPlatformTreasury(
    address platformTreasury_
  ) external onlySuperAdmin {
    if (platformTreasury_ == address(0)) {
      _revert(PlatformTreasuryCannotBeAddressZero.selector);
    }
    platformTreasury = platformTreasury_;

    emit PlatformTreasurySet(platformTreasury_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->DROPS
   * @dev (function) setDropExpiryInDays   Setter for the number of days that must pass since a drop was last changed
   *                                       before it can be removed from storage
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param dropExpiryInDays_              The number of days that must pass for a submitted drop to be considered expired
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setDropExpiryInDays(
    uint32 dropExpiryInDays_
  ) external onlyPlatformAdmin {
    dropExpiryInDays = dropExpiryInDays_;

    emit DropExpiryInDaysSet(dropExpiryInDays_);
  }

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
  function withdrawETHFromModules(
    address[] calldata moduleAddresses_
  ) external onlyPlatformAdmin {
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IPrimarySaleModule(moduleAddresses_[i]).transferETHBalanceToTreasury(
        platformTreasury
      );
    }
    emit ModuleETHBalancesTransferred(moduleAddresses_);
  }

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
  ) external onlyPlatformAdmin {
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IPrimarySaleModule(moduleAddresses_[i]).transferERC20BalanceToTreasury(
        platformTreasury,
        IERC20(tokenContract_)
      );
    }
    emit ModuleERC20BalancesTransferred(moduleAddresses_, tokenContract_);
  }

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
  ) external onlyPlatformAdmin {
    if (
      moduleAddresses_.length != startTimes_.length ||
      startTimes_.length != endTimes_.length
    ) {
      _revert(ListLengthMismatch.selector);
    }
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      if (startTimes_[i] != 0) {
        IPrimarySaleModule(moduleAddresses_[i]).setPhaseStart(
          uint32(startTimes_[i])
        );
      }
      if (endTimes_[i] != 0) {
        IPrimarySaleModule(moduleAddresses_[i]).setPhaseEnd(
          uint32(endTimes_[i])
        );
      }
    }
    emit ModulePhaseTimesUpdated(moduleAddresses_, startTimes_, endTimes_);
  }

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
  ) external onlyPlatformAdmin {
    if (moduleAddresses_.length != maxSupplys_.length) {
      _revert(ListLengthMismatch.selector);
    }
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IPrimarySaleModule(moduleAddresses_[i]).setPhaseMaxSupply(
        uint24(maxSupplys_[i])
      );
    }
    emit ModulePhaseMaxSupplysUpdated(moduleAddresses_, maxSupplys_);
  }

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
  ) external onlyPlatformAdmin {
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IPrimarySaleModule(moduleAddresses_[i]).setMetadropOracleAddress(
        metadropOracleAddress_
      );
    }
    emit ModuleOracleAddressUpdated(moduleAddresses_, metadropOracleAddress_);
  }

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
  ) external onlyPlatformAdmin {
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IPrimarySaleModule(moduleAddresses_[i]).setAntiSybilOff();
    }
    emit ModuleAntiSybilOff(moduleAddresses_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) updateAntiSybilOnOnModules     Allow platform admin to turn on anti-sybil protection on modules
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updateAntiSybilOnOnModules(
    address[] calldata moduleAddresses_
  ) external onlyPlatformAdmin {
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IPrimarySaleModule(moduleAddresses_[i]).setAntiSybilOn();
    }
    emit ModuleAntiSybilOn(moduleAddresses_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) updateEPSOffOnModules     Allow platform admin to turn off EPS on modules
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updateEPSOffOnModules(
    address[] calldata moduleAddresses_
  ) external onlyPlatformAdmin {
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IPrimarySaleModule(moduleAddresses_[i]).setEPSOff();
    }
    emit ModuleEPSOff(moduleAddresses_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) updateEPSOnOnModules     Allow platform admin to turn on EPS on modules
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updateEPSOnOnModules(
    address[] calldata moduleAddresses_
  ) external onlyPlatformAdmin {
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IPrimarySaleModule(moduleAddresses_[i]).setEPSOn();
    }
    emit ModuleEPSOn(moduleAddresses_);
  }

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
  ) external onlyPlatformAdmin {
    if (moduleAddresses_.length != newPublicMintPrices_.length) {
      _revert(ListLengthMismatch.selector);
    }
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IPublicMintByMetadrop(moduleAddresses_[i]).updatePublicMintPrice(
        newPublicMintPrices_[i]
      );
    }
    emit ModulePublicMintPricesUpdated(moduleAddresses_, newPublicMintPrices_);
  }

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
  ) external onlyPlatformAdmin {
    if (moduleAddresses_.length != merkleRoots_.length) {
      _revert(ListLengthMismatch.selector);
    }
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IListMintByMetadrop(moduleAddresses_[i]).setList(merkleRoots_[i]);
    }
    emit ModuleMerkleRootsUpdated(moduleAddresses_, merkleRoots_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->MODULES
   * @dev (function) pauseDeployedContract   Call pause on deployed contracts
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param moduleAddresses_       An array of module addresses
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function pauseDeployedContract(
    address[] calldata moduleAddresses_
  ) external onlyPlatformAdmin {
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IPausable(moduleAddresses_[i]).pause();
    }
  }

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
  ) external onlyPlatformAdmin {
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      IPausable(moduleAddresses_[i]).unpause();
    }
  }

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
  ) external onlyPlatformAdmin {
    IAuctionByMetadrop(module_).setAuctionFinalFloorDetails(
      endAuctionFloorPrice_,
      endAuctionAboveFloorBidQuantity_,
      endAuctionLastFloorPosition_,
      endAuctionRunningTotalAtLastFloorPosition_
    );
  }

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
  ) external onlyPlatformAdmin returns (bool success) {
    for (uint256 i = 0; i < moduleAddresses_.length; i++) {
      address to = moduleAddresses_[i];
      assembly {
        success := call(
          txGas_,
          to,
          value_,
          add(data_, 0x20),
          mload(data_),
          0,
          0
        )
      }
      if (!success) {
        revert AuxCallFailed(moduleAddresses_, value_, data_, txGas_);
      }
    }
    emit AuxCallSucceeded(moduleAddresses_, value_, data_, txGas_);
  }

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
  function withdrawETH(uint256 amount_) external onlyPlatformAdmin {
    (bool success, ) = platformTreasury.call{value: amount_}("");
    require(success, "Transfer failed");
  }

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
  function withdrawERC20(
    IERC20 token_,
    uint256 amount_
  ) external onlyPlatformAdmin {
    token_.safeTransfer(platformTreasury, amount_);
  }

  /** ====================================================================================================================
   *                                                    VRF SERVER
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) requestVRFRandomness  Get the metadata start position for use on reveal of the calling collection
   * _____________________________________________________________________________________________________________________
   */
  function requestVRFRandomness() external payable {
    // Can only be called by a deployed collection:
    if (deployedNFTContracts[msg.sender] = true) {
      if (vrfMode == 0) {
        // Chainlink
        addressForChainlinkVRFRequestId[
          vrfCoordinatorInterface.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            vrfRequestConfirmations,
            vrfCallbackGasLimit,
            vrfNumWords
          )
        ] = msg.sender;
      } else {
        // aarng
        addressForArrngVRFRequestId[
          arrngController.requestRandomWords{value: msg.value}(vrfNumWords)
        ] = msg.sender;
      }
    } else {
      _revert(MetadropModulesOnly.selector);
    }
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                                -->VRF
   * @dev (function) fulfillRandomWords  Callback from the chainlinkv2 / arrng oracle with randomness. We then forward
   * this to the requesting contract
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param requestId_      The Id of this request (this contract will submit a single request)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param randomWords_    The random words returned from chainlink
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function fulfillRandomWords(
    uint256 requestId_,
    uint256[] memory randomWords_
  ) internal override(ArrngConsumer, VRFConsumerBaseV2) {
    if (_msgSender() == address(arrngController)) {
      INFTByMetadrop(addressForArrngVRFRequestId[requestId_])
        .fulfillRandomWords(requestId_, randomWords_);
    } else {
      INFTByMetadrop(addressForChainlinkVRFRequestId[requestId_])
        .fulfillRandomWords(requestId_, randomWords_);
    }
  }

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
    string memory templateDescription_
  ) public onlyPlatformAdmin {
    if (address(contractAddress_) == address(0)) {
      _revert(TemplateCannotBeAddressZero.selector);
    }

    uint256 nextTemplateNumber = contractTemplates.length;
    contractTemplates.push(
      Template(
        TemplateStatus.live,
        uint16(nextTemplateNumber),
        uint32(block.timestamp),
        contractAddress_,
        templateDescription_
      )
    );

    emit TemplateAdded(
      TemplateStatus.live,
      nextTemplateNumber,
      block.timestamp,
      contractAddress_,
      templateDescription_
    );
  }

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
  ) public onlyPlatformAdmin {
    if (contractTemplates[templateId_].templateAddress == address(0)) {
      _revert(TemplateNotFound.selector);
    }
    address oldTemplateAddress = contractTemplates[templateId_].templateAddress;
    contractTemplates[templateId_].templateAddress = contractAddress_;
    emit TemplateUpdated(templateId_, oldTemplateAddress, contractAddress_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                          -->TEMPLATES
   * @dev (function) terminateTemplate  Mark a template as terminated
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param templateNumber_              The number of the template to be marked as terminated
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function terminateTemplate(
    uint16 templateNumber_
  ) external onlyPlatformAdmin {
    contractTemplates[templateNumber_].status = TemplateStatus.terminated;

    emit TemplateTerminated(templateNumber_);
  }

  /** ====================================================================================================================
   *                                                    DROP CREATION
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->DROPS
   * @dev (function) removeExpiredDropDetails  A review admin user can remove details for a drop that has expired.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param dropId_              The drop Id for which details are to be removed
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function removeExpiredDropDetails(
    string calldata dropId_
  ) external onlyReviewAdmin {
    // Drop ID must exist:
    require(
      dropDetailsByDropId[dropId_].lastChangedDate != 0,
      "Drop Review: drop ID does not exist"
    );

    // Last changed date must be the expiry period in the past (or greater)
    require(
      dropDetailsByDropId[dropId_].lastChangedDate <
        (block.timestamp - (dropExpiryInDays * 1 days)),
      "Drop Review: drop ID does not exist"
    );

    delete dropDetailsByDropId[dropId_];

    emit DropDetailsDeleted(dropId_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->DROPS
   * @dev (function) approveDrop  A review admin user can approve the drop.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param dropId_              The drop Id being approved
   * ---------------------------------------------------------------------------------------------------------------------
   * @param projectOwner_        Address of the project owner
   * ---------------------------------------------------------------------------------------------------------------------
   * @param dropConfigHash_      The config hash for this drop
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function approveDrop(
    string calldata dropId_,
    address projectOwner_,
    bytes32 dropConfigHash_
  ) external onlyReviewAdmin {
    if (projectOwner_ == address(0)) {
      _revert(ProjectOwnerCannotBeAddressZero.selector);
    }
    dropDetailsByDropId[dropId_] = DropApproval(
      DropStatus.approved,
      uint32(block.timestamp),
      projectOwner_,
      dropConfigHash_
    );

    emit DropApproved(dropId_, projectOwner_, dropConfigHash_);
  }

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
   * _____________________________________________________________________________________________________________________
   */
  function createDrop(
    string calldata dropId_,
    NFTModuleConfig calldata nftModule_,
    PrimarySaleModuleConfig[] calldata primarySaleModulesConfig_,
    RoyaltySplitterModuleConfig calldata royaltyPaymentSplitterModule_,
    bytes32 salesPageHash_,
    address customNftAddress_,
    string[2] calldata collectionURIs_
  ) external payable {
    // Check the fee:
    require(msg.value == dropFeeETH, "Incorrect ETH payment");

    // Get the details from storage:
    DropApproval memory currentDrop = dropDetailsByDropId[dropId_];

    // We can only proceed if this drop is set to 'approved'
    require(
      currentDrop.status == DropStatus.approved,
      "Drop creation: must be approved"
    );

    // We can only proceed if this is being called by the project owner:
    require(
      currentDrop.dropOwnerAddress == msg.sender,
      "Drop creation: must be submitted by project owner"
    );

    dropDetailsByDropId[dropId_].status = DropStatus.deployed;

    // We can only proceed if the hash of the passed configuration matches that stored
    // on chain from the project approval
    require(
      configHashMatches(
        dropId_,
        nftModule_,
        primarySaleModulesConfig_,
        royaltyPaymentSplitterModule_,
        salesPageHash_,
        customNftAddress_
      ),
      "Drop creation: passed config does not match approved"
    );

    // ---------------------------------------------
    //
    // ROYALTY
    //
    // ---------------------------------------------

    // Create the royalty payment splitter contract clone instance:
    RoyaltyDetails memory royaltyInfo = _createRoyaltyPaymentSplitterContract(
      royaltyPaymentSplitterModule_
    );

    // ---------------------------------------------
    //
    // PRIMARY SALE MODULES
    //
    // ---------------------------------------------
    //

    // Array to hold addresses of created primary sale modules:
    PrimarySaleModuleInstance[]
      memory primarySaleModuleInstances = new PrimarySaleModuleInstance[](
        primarySaleModulesConfig_.length
      );

    // Iterate over the received primary sale modules, instansiate and initialise:
    for (uint256 i = 0; i < primarySaleModulesConfig_.length; i++) {
      primarySaleModuleInstances[i].instanceAddress = payable(
        contractTemplates[primarySaleModulesConfig_[i].templateId]
          .templateAddress
      ).clone();

      primarySaleModuleInstances[i].instanceDescription = contractTemplates[
        primarySaleModulesConfig_[i].templateId
      ].templateDescription;

      // Initialise storage data:
      _initialisePrimarySaleModule(
        primarySaleModuleInstances[i].instanceAddress,
        primarySaleModulesConfig_[i].configData,
        i + 1
      );
    }

    // ---------------------------------------------
    //
    // NFT
    //
    // ---------------------------------------------
    //

    // Create the NFT clone instance:
    address newNFTInstance = _createNFTContract(
      primarySaleModuleInstances,
      nftModule_,
      royaltyInfo,
      customNftAddress_,
      collectionURIs_
    );

    // Iterate over the primary sale modules, and add the NFT address
    for (uint256 i = 0; i < primarySaleModuleInstances.length; i++) {
      IPrimarySaleModule(primarySaleModuleInstances[i].instanceAddress)
        .setNFTAddress(newNFTInstance);
    }

    emit DropDeployed(
      dropId_,
      newNFTInstance,
      primarySaleModuleInstances,
      royaltyInfo.newRoyaltyPaymentSplitterInstance
    );
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->DROPS
   * @dev (function) _initialisePrimarySaleModule  Load initial values to a sale module
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param instanceAddress_           The module to be initialised
   * ---------------------------------------------------------------------------------------------------------------------
   * @param configData_                The configuration data for this module
   * ---------------------------------------------------------------------------------------------------------------------
   * @param phaseId_                   The ID of this phase
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function _initialisePrimarySaleModule(
    address instanceAddress_,
    bytes calldata configData_,
    uint256 phaseId_
  ) internal {
    IPrimarySaleModule(instanceAddress_).initialisePrimarySaleModule(
      configData_,
      pauseCutOffInDays,
      metadropOracleAddress,
      messageValidityInMinutes,
      phaseId_
    );
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->DROPS
   * @dev (function) _createRoyaltyPaymentSplitterContract  Create the royalty payment splitter.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param royaltyModule_     The configuration data for the royalty module
   * ---------------------------------------------------------------------------------------------------------------------
   * @return royaltyInfo_   The contract address for the splitter and the decoded royalty from sales in basis points
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function _createRoyaltyPaymentSplitterContract(
    RoyaltySplitterModuleConfig calldata royaltyModule_
  ) internal returns (RoyaltyDetails memory royaltyInfo_) {
    // Template 65535 indicates this module is not required
    if (royaltyModule_.templateId == type(uint16).max) {
      royaltyInfo_.newRoyaltyPaymentSplitterInstance = address(0);
      royaltyInfo_.royaltyFromSalesInBasisPoints = 0;
      return (royaltyInfo_);
    }

    address payable targetRoyaltySplitterTemplate = contractTemplates[
      royaltyModule_.templateId
    ].templateAddress;

    // Create the clone vesting contract:
    address newRoyaltySplitterInstance = targetRoyaltySplitterTemplate.clone();

    uint96 royaltyFromSalesInBasisPoints = IRoyaltyPaymentSplitterByMetadrop(
      payable(newRoyaltySplitterInstance)
    ).initialiseRoyaltyPaymentSplitter(royaltyModule_, platformTreasury);

    royaltyInfo_.newRoyaltyPaymentSplitterInstance = newRoyaltySplitterInstance;
    royaltyInfo_.royaltyFromSalesInBasisPoints = royaltyFromSalesInBasisPoints;

    return (royaltyInfo_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->DROPS
   * @dev (function) _createNFTContract  Create the NFT contract
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param primarySaleModules_          An array of primary sale module addresses for this NFT
   * ---------------------------------------------------------------------------------------------------------------------
   * @param nftModule_                   Configuration details for the NFT
   * ---------------------------------------------------------------------------------------------------------------------
   * @param royaltyInfo_                 Royalty details
   * ---------------------------------------------------------------------------------------------------------------------
   * @param customNftAddress_            The custom NFT address if there is one. If we are not using a metadrop template
   *                                     this function will return this address (keeping the process identical for custom
   *                                     and standard drops)
   * ---------------------------------------------------------------------------------------------------------------------
   * @param collectionURIs_              An array of collection URIs (pre-reveal, ipfs and arweave)
   * ---------------------------------------------------------------------------------------------------------------------
   * @return nftContract_                The address of the deployed NFT contract clone
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function _createNFTContract(
    PrimarySaleModuleInstance[] memory primarySaleModules_,
    NFTModuleConfig memory nftModule_,
    RoyaltyDetails memory royaltyInfo_,
    address customNftAddress_,
    string[2] calldata collectionURIs_
  ) internal returns (address nftContract_) {
    // Template type(uint16).max indicates this module is not required
    if (nftModule_.templateId == type(uint16).max) {
      return (customNftAddress_);
    }

    address newNFTInstance = contractTemplates[nftModule_.templateId]
      .templateAddress
      .clone();

    // Initialise storage data:
    INFTByMetadrop(newNFTInstance).initialiseNFT(
      msg.sender,
      primarySaleModules_,
      nftModule_,
      royaltyInfo_,
      collectionURIs_,
      pauseCutOffInDays
    );
    return newNFTInstance;
  }

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
    address customNftAddress_
  ) public view returns (bool matches_) {
    // Create the hash of the passed data for comparison:
    bytes32 passedConfigHash = createConfigHash(
      dropId_,
      nftModule_,
      primarySaleModulesConfig_,
      royaltyPaymentSplitterModule_,
      salesPageHash_,
      customNftAddress_
    );
    // Must equal the stored hash:
    return (passedConfigHash == dropDetailsByDropId[dropId_].configHash);
  }

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
    address customNftAddress_
  ) public pure returns (bytes32 configHash_) {
    // Hash the primary sales module data
    for (uint256 i = 0; i < primarySaleModulesConfig_.length; i++) {
      configHash_ = keccak256(
        abi.encodePacked(
          configHash_,
          primarySaleModulesConfig_[i].templateId,
          primarySaleModulesConfig_[i].configData
        )
      );
    }

    configHash_ = keccak256(
      // Hash remaining items:
      abi.encodePacked(
        configHash_,
        dropId_,
        nftModule_.templateId,
        nftModule_.configData,
        nftModule_.vestingData,
        royaltyPaymentSplitterModule_.templateId,
        royaltyPaymentSplitterModule_.configData,
        salesPageHash_,
        customNftAddress_
      )
    );

    return (configHash_);
  }
}

