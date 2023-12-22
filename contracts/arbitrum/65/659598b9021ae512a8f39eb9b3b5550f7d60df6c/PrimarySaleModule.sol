// SPDX-License-Identifier: BUSL 1.0
// Metadrop Contracts (v2.0.0)

/**
 *
 * @title PrimarySaleModule.sol. This contract is the base primary sale module contract
 * for the metadrop drop platform. All primary sale modules inherit from this contract
 *
 * @author metadrop https://metadrop.com/
 *
 */

pragma solidity 0.8.19;

import {Strings} from "./Strings.sol";
import {SignatureChecker} from "./SignatureChecker.sol";
import {MerkleProof} from "./MerkleProof.sol";
import {IEPSDelegationRegister} from "./IEPSDelegationRegister.sol";
import {Pausable} from "./Pausable.sol";
import {IPrimarySaleModule, IERC20} from "./IPrimarySaleModule.sol";
import {INFTByMetadrop} from "./INFTByMetadrop.sol";
import {Ownable} from "./Ownable.sol";

/**
 *
 * @dev Inheritance details:
 *      IPrimarySaleModule         Interface for this module
 *      Pausable                   Allow modules to be paused
 *
 *
 */

contract PrimarySaleModule is IPrimarySaleModule, Pausable {
  using Strings for uint256;

  uint256 private constant BASIS_POINTS_DENOMINATOR = 10000;

  // EPS Register
  IEPSDelegationRegister public immutable epsRegister;
  // Slot 1 - NFT and phase details (pack together for warm slot reads)
  //  160
  //    8
  //   24
  //   32
  //   32
  //= 256
  INFTByMetadrop public nftContract;
  // Id of this phase:
  uint8 public phaseId;
  // The number of NFTs that can be minted in this phase:
  uint24 public phaseMaxSupply;
  // Start time for  minting
  uint32 public phaseStart;
  // End time for minting. Note that this can be passed as maxUint32, which is a mint
  // unlimited by time
  uint32 public phaseEnd;

  // Slot 2 - anti-bot-proection and fees (pack together for warm slot reads)
  //  160
  //    8
  //    8
  //    8
  //   56
  //   16
  //= 256

  // The metadrop admin signer used as a trusted oracle (e.g. for anti-bot protection)
  address public metadropOracleAddress;
  // Bool to indicate if we are using the oracle for anti-bot protection
  bool public useOracleToAntiSybil;
  // Bool to indicate if EPS is in use in this drop
  bool public useEPS;
  // The oracle signed message validity period:
  uint8 public messageValidityInMinutes;
  // The metadrop fee per mint
  uint56 public metadropFeePerMint;
  // The metadrop share of primary sales proceeds in basis points
  uint16 public metadropPrimaryShareInBasisPoints;

  // Slot 3 - not accessed in mints
  //  160
  //   32
  //    8
  //= 200
  address public factory;
  // Point at which contract cannot be paused:
  uint32 public pauseCutoffInDays;
  // Bool that controls initialisation and only allows it to occur ONCE. This is
  // needed as this contract is clonable, threfore the constructor is not called
  // on cloned instances. We setup state of this contract through the initialise
  // function.
  bool public initialised;

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
   * _____________________________________________________________________________________________________________________
   */
  constructor(address epsRegister_) {
    epsRegister = IEPSDelegationRegister(epsRegister_);
    initialised = true;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                         -->INITIALISE
   * @dev (function) initialisePrimarySaleModule  Defined here and must be overriden in child contracts
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param configData_               The drop specific configuration for this module. This is decoded and used to set
   *                                  configuration for this metadrop drop
   * ---------------------------------------------------------------------------------------------------------------------
   * @param pauseCutoffInDays_        The maximum number of days after drop deployment that this contract can be paused
   * ---------------------------------------------------------------------------------------------------------------------
   * @param metadropOracleAddress_    The trusted metadrop signer. This is used with anti-bot protection
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageValidityInSeconds_ The validity period of a signed message. This is used with anti-bot protection
   * ---------------------------------------------------------------------------------------------------------------------
   * @param phaseId_                  The ID of this phase, used for tracking supply
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function initialisePrimarySaleModule(
    bytes calldata configData_,
    uint256 pauseCutoffInDays_,
    address metadropOracleAddress_,
    uint256 messageValidityInSeconds_,
    uint256 phaseId_
  ) public virtual {
    // Must be overridden
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                         -->INITIALISE
   * @dev (function) _initialisePrimarySaleModuleBase  Base configuration load that is shared across all primary sale
   *                                                   modules
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param pauseCutoffInDays_        The maximum number of days after drop deployment that this contract can be paused
   * ---------------------------------------------------------------------------------------------------------------------
   * @param start_                    The start date of this primary sale module
   * ---------------------------------------------------------------------------------------------------------------------
   * @param end_                      The end date of this primary sale module
   * ---------------------------------------------------------------------------------------------------------------------
   * @param metadropPerMintFee_       The metadrop fee for each mint
   * ---------------------------------------------------------------------------------------------------------------------
   * @param metadropPrimaryShareInBasisPoints_       The metadrop share of total primary proceeds
   * ---------------------------------------------------------------------------------------------------------------------
   * @param phaseMaxSupply_           The max supply for this phase
   * ---------------------------------------------------------------------------------------------------------------------
   * @param metadropOracleAddress_    The trusted metadrop signer. This is used with anti-bot protection
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageValidityInMinutes_ The validity period of a signed message. This is used with anti-bot protection
   * ---------------------------------------------------------------------------------------------------------------------
   * @param phaseId_                  The ID of this phase
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function _initialisePrimarySaleModuleBase(
    uint256 pauseCutoffInDays_,
    uint256 start_,
    uint256 end_,
    uint256 phaseMaxSupply_,
    uint256 metadropPerMintFee_,
    uint256 metadropPrimaryShareInBasisPoints_,
    address metadropOracleAddress_,
    uint256 messageValidityInMinutes_,
    uint256 phaseId_
  ) internal {
    if (initialised) {
      _revert(AlreadyInitialised.selector);
    }

    pauseCutoffInDays = uint32(pauseCutoffInDays_);

    phaseId = uint8(phaseId_);
    phaseStart = uint32(start_);
    phaseEnd = uint32(end_);
    phaseMaxSupply = uint24(phaseMaxSupply_);

    metadropOracleAddress = metadropOracleAddress_;
    messageValidityInMinutes = uint8(messageValidityInMinutes_);

    metadropFeePerMint = uint56(metadropPerMintFee_);
    metadropPrimaryShareInBasisPoints = uint16(
      metadropPrimaryShareInBasisPoints_
    );

    useOracleToAntiSybil = true;
    useEPS = true;
    factory = msg.sender;

    initialised = true;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                     -->ACCESS CONTROL
   * @dev (modifier) onlyFactory. The associated action can only be taken by the factory
   *
   * _____________________________________________________________________________________________________________________
   */
  modifier onlyFactory() {
    if (msg.sender != factory) _revert(CallerIsNotFactory.selector);
    _;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                     -->ACCESS CONTROL
   * @dev (modifier) onlyFactoryOrProjectOwner. The associated action can only be taken by the factory or project owner.
   *
   * _____________________________________________________________________________________________________________________
   */
  modifier onlyFactoryOrProjectOwner() {
    if (msg.sender != factory && !isProjectOwner(msg.sender))
      _revert(CallerIsNotFactoryOrProjectOwner.selector);
    _;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->SETUP
   * @dev (function) setNFTAddress    Set the NFT contract for this drop
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param nftContract_           The deployed NFT contract
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setNFTAddress(address nftContract_) external onlyFactory {
    if (nftContract == INFTByMetadrop(address(0))) {
      nftContract = INFTByMetadrop(nftContract_);
    } else {
      _revert(AddressAlreadySet.selector);
    }
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->SETUP
   * @dev (function) isProjectOwner  Get the project owner associated with this drop. The project owner is the ownable
   *                                 owner on the NFT contract associated with this drop.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param queryAddress_            The queried address is / isn't the project owner
   * ---------------------------------------------------------------------------------------------------------------------
   * @return bool                    The queried address is / isn't the project owner
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function isProjectOwner(address queryAddress_) public view returns (bool) {
    return (queryAddress_ == Ownable(address(nftContract)).owner());
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->SETUP
   * @dev (function) getPhaseStartAndEnd  Get the start and end times for this phase
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return phaseStart_             The phase start time
   * ---------------------------------------------------------------------------------------------------------------------
   * @return phaseEnd_               The phase end time
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function getPhaseStartAndEnd()
    external
    view
    returns (uint256 phaseStart_, uint256 phaseEnd_)
  {
    return (phaseStart, phaseEnd);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) phaseQuantityMinted  Get the number of mints for this phase
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return phaseQuantityMinted_               The number of mints for this phase
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function phaseQuantityMinted()
    external
    view
    returns (uint256 phaseQuantityMinted_)
  {
    return nftContract.phaseMintCount(phaseId);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->SETUP
   * @dev (function) setPhaseStart  Set the phase start for this drop (platform admin only)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param phaseStart_             The phase start time
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setPhaseStart(uint32 phaseStart_) external onlyFactory {
    phaseStart = phaseStart_;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->SETUP
   * @dev (function) setPhaseEnd    Set the phase start for this drop (platform admin only)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param phaseEnd_               The phase end time
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setPhaseEnd(uint32 phaseEnd_) external onlyFactory {
    phaseEnd = phaseEnd_;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->SETUP
   * @dev (function) setPhaseMaxSupply     Set the phase start for this drop (platform admin only)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param phaseMaxSupply_                The phase supply
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setPhaseMaxSupply(uint24 phaseMaxSupply_) external onlyFactory {
    phaseMaxSupply = phaseMaxSupply_;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->SETUP
   * @dev (function) phaseMintStatus    The status of the deployed primary sale module
   * _____________________________________________________________________________________________________________________
   */
  function phaseMintStatus() public view returns (MintStatus status) {
    return _primarySaleStatus(phaseStart, phaseEnd);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->SETUP
   * @dev (function) _primarySaleStatus    Return the status of the mint type
   * _____________________________________________________________________________________________________________________
   */
  function _primarySaleStatus(
    uint256 start_,
    uint256 end_
  ) internal view returns (MintStatus) {
    // Explicitly check for open before anything else. This is the only valid path to making a
    // state change, so keep the gas as low as possible for the code path through 'open'
    if (block.timestamp >= (start_) && block.timestamp <= (end_)) {
      return (MintStatus.open);
    }

    if ((start_ + end_) == 0) {
      return (MintStatus.notEnabled);
    }

    if (block.timestamp > end_) {
      return (MintStatus.finished);
    }

    if (block.timestamp < start_) {
      return (MintStatus.notYetOpen);
    }

    return (MintStatus.unknown);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) _mint         Called from all primary sale modules: perform minting!
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
   * @param quantityToMint_        The number of NFTs being minted in this call
   * ---------------------------------------------------------------------------------------------------------------------
   * @param unitPrice_             The per NFT price for this mint.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageTimeStamp_      The timestamp of the signed message
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageHash_           The message hash signed by the trusted oracle signer. This will be the keccack256 hash
   *                               of received data about this social mint.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageSignature_      The signed message from the backend oracle signer for validation.
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function _mint(
    address caller_,
    address recipient_,
    address allowanceAddress_,
    uint256 quantityToMint_,
    uint256 unitPrice_,
    uint256 messageTimeStamp_,
    bytes32 messageHash_,
    bytes calldata messageSignature_,
    uint256 payment_
  ) internal whenNotPaused {
    if (phaseMintStatus() != MintStatus.open)
      _revert(ThisMintIsClosed.selector);

    if (useOracleToAntiSybil) {
      // Check that this signature is from the oracle signer:
      if (!_validSignature(messageHash_, messageSignature_)) {
        _revert(InvalidOracleSignature.selector);
      }

      // Check that the signature has not expired:
      uint256 messageValidityInSeconds = messageValidityInMinutes;
      messageValidityInSeconds = messageValidityInSeconds * 60;
      if ((messageTimeStamp_ + messageValidityInSeconds) < block.timestamp) {
        _revert(OracleSignatureHasExpired.selector);
      }

      // Signature is valid. Check that the passed parameters match the hash that was signed:
      if (
        !_parametersMatchHash(
          recipient_,
          quantityToMint_,
          msg.sender,
          messageTimeStamp_,
          messageHash_
        )
      ) {
        _revert(ParametersDoNotMatchSignedMessage.selector);
      }
    }

    // Work out how much to remit to the NFT contract for this mint operation:
    uint256 amountToRemit = payment_;
    if (metadropFeePerMint != 0) {
      uint256 perMintFee = metadropFeePerMint * quantityToMint_;
      if (amountToRemit < perMintFee) {
        _revert(PaymentMustCoverPerMintFee.selector);
      }
      amountToRemit -= perMintFee;
    }

    if (amountToRemit != 0 && metadropPrimaryShareInBasisPoints != 0) {
      uint256 shareBasedFee = (amountToRemit *
        metadropPrimaryShareInBasisPoints) / BASIS_POINTS_DENOMINATOR;
      amountToRemit -= shareBasedFee;
    }

    nftContract.metadropMint{value: amountToRemit}(
      caller_,
      recipient_,
      allowanceAddress_,
      quantityToMint_,
      unitPrice_,
      phaseId,
      phaseMaxSupply
    );
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) _validSignature         Checks the the signature on the signed message is from the metadrop oracle
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageHash_           The message hash signed by the trusted oracle signer. This will be the keccack256 hash
   *                               of received data about this social mint
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageSignature_      The signed message from the backend oracle signer for validation.
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function _validSignature(
    bytes32 messageHash_,
    bytes memory messageSignature_
  ) internal view returns (bool) {
    bytes32 ethSignedMessageHash = keccak256(
      abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash_)
    );

    // Check the signature is valid:
    return (
      SignatureChecker.isValidSignatureNow(
        metadropOracleAddress,
        ethSignedMessageHash,
        messageSignature_
      )
    );
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) _parametersMatchHash      Checks the the signature on the signed message is from the metadrop oracle
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param recipient_             The address that will receive new assets
   * ---------------------------------------------------------------------------------------------------------------------
   * @param quantityToMint_        The number of NFTs being minted in this call
   * ---------------------------------------------------------------------------------------------------------------------
   * @param caller_                The msg.sender on this call
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageTimeStamp_      The timestamp on the message
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageHash_           The message hash signed by the trusted oracle signer. This will be the keccack256 hash
   *                               of received data about this social mint
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function _parametersMatchHash(
    address recipient_,
    uint256 quantityToMint_,
    address caller_,
    uint256 messageTimeStamp_,
    bytes32 messageHash_
  ) internal view returns (bool) {
    return (
      (keccak256(
        abi.encodePacked(
          recipient_,
          quantityToMint_,
          caller_,
          messageTimeStamp_,
          address(this)
        )
      ) == messageHash_)
    );
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->FINANCE
   * @dev (function) transferETHBalanceToTreasury        A transfer function to allow  all ETH to be withdrawn
   *                                                     to vesting.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param treasury_           The treasury address
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function transferETHBalanceToTreasury(
    address treasury_
  ) external onlyFactory {
    (bool success, ) = treasury_.call{value: address(this).balance}("");
    if (!success) {
      _revert(TransferFailed.selector);
    }
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->FINANCE
   * @dev (function) transferERC20BalanceToTreasury     A transfer function to allow ERC20s to be withdrawn to the
   *                                             treasury.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param treasury_          The treasury address
   * ---------------------------------------------------------------------------------------------------------------------
   * @param token_             The token to withdraw
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function transferERC20BalanceToTreasury(
    address treasury_,
    IERC20 token_
  ) external onlyFactory {
    bool success = token_.transfer(treasury_, token_.balanceOf(address(this)));
    if (!success) {
      _revert(TransferFailed.selector);
    }
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) setMetadropOracleAddress   Allow platform admin to update trusted oracle address
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param metadropOracleAddress_         The new metadrop oracle address
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setMetadropOracleAddress(
    address metadropOracleAddress_
  ) external onlyFactory {
    if (metadropOracleAddress_ == address(0)) {
      _revert(CannotSetToZeroAddress.selector);
    }
    metadropOracleAddress = metadropOracleAddress_;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) setAntiSybilOff     Allow platform admin to turn off anti-sybil protection
   * _____________________________________________________________________________________________________________________
   */
  function setAntiSybilOff() external onlyFactory {
    useOracleToAntiSybil = false;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) setAntiSybilOff     Allow platform admin to turn ON anti-sybil protection
   * _____________________________________________________________________________________________________________________
   */
  function setAntiSybilOn() external onlyFactory {
    useOracleToAntiSybil = true;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) setEPSOff    Allow platform admin to turn off EPS
   * _____________________________________________________________________________________________________________________
   */
  function setEPSOff() external onlyFactory {
    useEPS = false;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) setEPSOff    Allow platform admin to turn ON EPS
   * _____________________________________________________________________________________________________________________
   */
  function setEPSOn() external onlyFactory {
    useEPS = true;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) pause    Allow platform admin to pause
   * _____________________________________________________________________________________________________________________
   */
  function pause() external onlyFactory {
    _pause();
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) unpause    Allow platform admin to unpause
   * _____________________________________________________________________________________________________________________
   */
  function unpause() external onlyFactory {
    _unpause();
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) receive   Reject eth of unkown source
   * _____________________________________________________________________________________________________________________
   */
  receive() external payable onlyFactory {}

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) fallback   Revert all fall backs
   * _____________________________________________________________________________________________________________________
   */
  fallback() external {
    revert();
  }
}

