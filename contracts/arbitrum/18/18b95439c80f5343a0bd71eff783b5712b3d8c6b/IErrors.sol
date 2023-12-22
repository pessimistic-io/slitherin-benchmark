// SPDX-License-Identifier: MIT
// Metadrop Contracts (v2.0.0)

/**
 *
 * @title IErrors.sol. Interface for error definitions used across the platform
 *
 * @author metadrop https://metadrop.com/
 *
 */

pragma solidity 0.8.19;

interface IErrors {
  enum BondingCurveErrorType {
    OK, //                                                  No error
    INVALID_NUMITEMS, //                                    The numItem value is 0
    SPOT_PRICE_OVERFLOW //                                  The updated spot price doesn't fit into 128 bits
  }

  error AdapterParamsMustBeEmpty(); //                      The adapter parameters on this LZ call must be empty.

  error AddressAlreadySet(); //                             The address being set can only be set once, and is already non-0.

  error AlreadyInitialised(); //                            The contract is already initialised: it cannot be initialised twice!

  error ApprovalCallerNotOwnerNorApproved(); //             The caller must own the token or be an approved operator.

  error ApprovalQueryForNonexistentToken(); //              The token does not exist.

  error AuctionStatusIsNotEnded(); //                       Throw if the action required the auction to be closed, and it isn't.

  error AuctionStatusIsNotOpen(); //                        Throw if the action requires the auction to be open, and it isn't.

  error AuxCallFailed(
    address[] modules,
    uint256 value,
    bytes data,
    uint256 txGas
  ); //                                                     An auxilliary call from the drop factory failed.

  error BalanceQueryForZeroAddress(); //                    Cannot query the balance for the zero address.

  error BidMustBeBelowTheFloorWhenReducingQuantity(); //    Only bids that are below the floor can reduce the quantity of the bid.

  error BidMustBeBelowTheFloorForRefundDuringAuction(); //  Only bids that are below the floor can be refunded during the auction.

  error BondingCurveError(BondingCurveErrorType error); //  An error of the type specified has occured in bonding curve processing.

  error CallerIsNotFactory(); //                            The caller of this function must match the factory address in storage.

  error CallerIsNotFactoryOrProjectOwner(); //              The caller of this function must match the factory address OR project owner address.

  error CallerIsNotTheOwner(); //                           The caller is not the owner of this contract.

  error CallerMustBeLzApp(); //                             The caller must be an LZ application.

  error CallerIsNotPlatformAdmin(address caller); //        The caller of this function must be part of the platformAdmin group.

  error CallerIsNotSuperAdmin(address caller); //           The caller of this function must match the superAdmin address in storage.

  error CallerIsNotReviewAdmin(address caller); //          The caller of this function must be part of the reviewAdmin group.

  error CannotSetNewOwnerToTheZeroAddress(); //             You can't set the owner of this contract to the zero address (address(0)).

  error CannotSetToZeroAddress(); //                        The corresponding address cannot be set to the zero address (address(0)).

  error CollectionAlreadyRevealed(); //                     The collection is already revealed; you cannot call reveal again.

  error ContractIsPaused(); //                              The call requires the contract to be unpaused, and it is paused.

  error ContractIsNotPaused(); //                           The call required the contract to be paused, and it is NOT paused.

  error DecreasedAllowanceBelowZero(); //                   The request would decrease the allowance below zero, and that is not allowed.

  error DestinationIsNotTrustedSource(); //                 The destination that is being called through LZ has not been set as trusted.

  error GasLimitIsTooLow(); //                              The gas limit for the LayerZero call is too low.

  error IncorrectConfirmationValue(); //                    You need to enter the right confirmation value to call this funtion (usually 69420).

  error IncorrectPayment(); //                              The function call did not include passing the correct payment.

  error InvalidAdapterParams(); //                          The current adapter params for LayerZero on this contract won't work :(.

  error InvalidAddress(); //                                An address being processed in the function is not valid.

  error InvalidEndpointCaller(); //                         The calling address is not a valid LZ endpoint. The LZ endpoint was set at contract creation
  //                                                        and cannot be altered after. Check the address LZ endpoint address on the contract.

  error InvalidMinGas(); //                                 The minimum gas setting for LZ in invalid.

  error InvalidOracleSignature(); //                        The signature provided with the contract call is not valid, either in format or signer.

  error InvalidPayload(); //                                The LZ payload is invalid

  error InvalidReceiver(); //                               The address used as a target for funds is not valid.

  error InvalidSourceSendingContract(); //                  The LZ message is being related from a source contract on another chain that is NOT trusted.

  error InvalidTotalShares(); //                            Total shares must equal 100 percent in basis points.

  error ListLengthMismatch(); //                            Two or more lists were compared and they did not match length.

  error NoTrustedPathRecord(); //                           LZ needs a trusted path record for this to work. What's that, you ask?

  error MaxBidQuantityIs255(); //                           Validation: as we use a uint8 array to track bid positions the max bid quantity is 255.

  error MaxPublicMintAllowanceExceeded(
    uint256 requested,
    uint256 alreadyMinted,
    uint256 maxAllowance
  ); //                                                     The calling address has requested a quantity that would exceed the max allowance.

  error MetadataIsLocked(); //                              The metadata on this contract is locked; it cannot be altered!

  error MetadropFactoryOnlyOncePerReveal(); //              This function can only be called (a) by the factory and, (b) just one time!

  error MetadropModulesOnly(); //                           Can only be called from a metadrop contract.

  error MetadropOracleCannotBeAddressZero(); //             The metadrop Oracle cannot be the zero address (address(0)).

  error MinGasLimitNotSet(); //                             The minimum gas limit for LayerZero has not been set.

  error MintERC2309QuantityExceedsLimit(); //               The `quantity` minted with ERC2309 exceeds the safety limit.

  error MintingIsClosedForever(); //                        Minting is, as the error suggests, so over (and locked forever).

  error MintToZeroAddress(); //                             Cannot mint to the zero address.

  error MintZeroQuantity(); //                              The quantity of tokens minted must be more than zero.

  error NoPaymentDue(); //                                  No payment is due for this address.

  error NoRefundForCaller(); //                             Error thrown when the calling address has no refund owed.

  error NoStoredMessage(); //                               There is no stored message matching the passed parameters.

  error OperationDidNotSucceed(); //                        The operation failed (vague much?).

  error OracleSignatureHasExpired(); //                     A signature has been provided but it is too old.

  error OwnershipNotInitializedForExtraData(); //           The `extraData` cannot be set on an uninitialized ownership slot.

  error OwnerQueryForNonexistentToken(); //                 The token does not exist.

  error ParametersDoNotMatchSignedMessage(); //             The parameters passed with the signed message do not match the message itself.

  error PauseCutOffHasPassed(); //                          The time period in which we can pause has passed; this contract can no longer be paused.

  error PaymentMustCoverPerMintFee(); //                    The payment passed must at least cover the per mint fee for the quantity requested.

  error PermitDidNotSucceed(); //                           The safeERC20 permit failed.

  error PlatformAdminCannotBeAddressZero(); //              We cannot use the zero address (address(0)) as a platformAdmin.

  error PlatformTreasuryCannotBeAddressZero(); //           The treasury address cannot be set to the zero address.

  error ProjectOwnerCannotBeAddressZero(); //               The project owner has to be a non zero address.

  error ProofInvalid(); //                                  The provided proof is not valid with the provided arguments.

  error QuantityExceedsRemainingCollectionSupply(); //      The requested quantity would breach the collection supply.

  error QuantityExceedsRemainingPhaseSupply(); //           The requested quantity would breach the phase supply.

  error QuantityExceedsMaxPossibleCollectionSupply(); //    The requested quantity would breach the maximum trackable supply

  error ReferralIdAlreadyUsed(); //                         This referral ID has already been used; they are one use only.

  error RequestingMoreThanRemainingAllocation(
    uint256 previouslyMinted,
    uint256 requested,
    uint256 remainingAllocation
  ); //                                                     Number of tokens requested for this mint exceeds the remaining allocation (taking the
  //                                                        original allocation from the list and deducting minted tokens).

  error ReviewAdminCannotBeAddressZero(); //                We cannot use the zero address (address(0)) as a platformAdmin.

  error RoyaltyFeeWillExceedSalePrice(); //                 The ERC2981 royalty specified will exceed the sale price.

  error ShareTotalCannotBeZero(); //                        The total of all the shares cannot be nothing.

  error SliceOutOfBounds(); //                              The bytes slice operation was out of bounds.

  error SliceOverflow(); //                                 The bytes slice operation overlowed.

  error SuperAdminCannotBeAddressZero(); //                 The superAdmin cannot be the sero address (address(0)).

  error TemplateCannotBeAddressZero(); //                   The address for a template cannot be address zero (address(0)).

  error TemplateNotFound(); //                              There is no template that matches the passed template Id.

  error ThisMintIsClosed(); //                              It's over (well, this mint is, anyway).

  error TotalSharesMustMatchDenominator(); //               The total of all shares must equal the denominator value.

  error TransferCallerNotOwnerNorApproved(); //             The caller must own the token or be an approved operator.

  error TransferFailed(); //                                The transfer has, you may be surprised to learn, failed.

  error TransferFromIncorrectOwner(); //                    The token must be owned by `from`.

  error TransferToNonERC721ReceiverImplementer(); //        Cannot safely transfer to a contract that does not implement the ERC721Receiver interface.

  error TransferToZeroAddress(); //                         Cannot transfer to the zero address.

  error UnrecognisedVRFMode(); //                           Currently supported VRF modes are 0: chainlink and 1: arrng

  error URIQueryForNonexistentToken(); //                   The token does not exist.

  error ValueExceedsMaximum(); //                           The value sent exceeds the maximum allowed (super useful explanation huh?).

  error VRFCoordinatorCannotBeAddressZero(); //             The VRF coordinator cannot be the zero address (address(0)).
}

