// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {IStableSwap} from "./IStableSwap.sol";
import {IConnectorManager} from "./IConnectorManager.sol";
import {SwapUtils} from "./SwapUtils.sol";

// ============= Enum =============

/// @notice Enum representing address role
// Returns uint
// None     - 0
// Router   - 1
// Watcher  - 2
// Admin    - 3
enum Role {
  None,
  Router,
  Watcher,
  Admin
}

/**
 * @notice Enum representing status of destination transfer
 * @dev Status is only assigned on the destination domain, will always be "none" for the
 * origin domains
 * @return uint - Index of value in enum
 */
enum DestinationTransferStatus {
  None, // 0
  Reconciled, // 1
  Executed, // 2
  Completed // 3 - executed + reconciled
}

// ============= Structs =============

struct TokenId {
  uint32 domain;
  bytes32 id;
}

/**
 * @notice These are the parameters that will remain constant between the
 * two chains. They are supplied on `xcall` and should be asserted on `execute`
 * @property to - The account that receives funds, in the event of a crosschain call,
 * will receive funds if the call fails.
 *
 * @param originDomain - The originating domain (i.e. where `xcall` is called). Must match nomad domain schema
 * @param destinationDomain - The final domain (i.e. where `execute` / `reconcile` are called). Must match nomad domain schema
 * @param canonicalDomain - The canonical domain of the asset you are bridging
 * @param to - The address you are sending funds (and potentially data) to
 * @param delegate - An address who can execute txs on behalf of `to`, in addition to allowing relayers
 * @param receiveLocal - If true, will use the local nomad asset on the destination instead of adopted.
 * @param callData - The data to execute on the receiving chain. If no crosschain call is needed, then leave empty.
 * @param slippage - Slippage user is willing to accept from original amount in expressed in BPS (i.e. if
 * a user takes 1% slippage, this is expressed as 1_000)
 * @param originSender - The msg.sender of the xcall
 * @param bridgedAmt - The amount sent over the bridge (after potential AMM on xcall)
 * @param normalizedIn - The amount sent to `xcall`, normalized to 18 decimals
 * @param nonce - The nonce on the origin domain used to ensure the transferIds are unique
 * @param canonicalId - The unique identifier of the canonical token corresponding to bridge assets
 */
struct TransferInfo {
  uint32 originDomain;
  uint32 destinationDomain;
  uint32 canonicalDomain;
  address to;
  address delegate;
  bool receiveLocal;
  bytes callData;
  uint256 slippage;
  address originSender;
  uint256 bridgedAmt;
  uint256 normalizedIn;
  uint256 nonce;
  bytes32 canonicalId;
}

/**
 * @notice
 * @param params - The TransferInfo. These are consistent across sending and receiving chains.
 * @param routers - The routers who you are sending the funds on behalf of.
 * @param routerSignatures - Signatures belonging to the routers indicating permission to use funds
 * for the signed transfer ID.
 * @param sequencer - The sequencer who assigned the router path to this transfer.
 * @param sequencerSignature - Signature produced by the sequencer for path assignment accountability
 * for the path that was signed.
 */
struct ExecuteArgs {
  TransferInfo params;
  address[] routers;
  bytes[] routerSignatures;
  address sequencer;
  bytes sequencerSignature;
}

/**
 * @notice Contains RouterFacet related state
 * @param approvedRouters - Mapping of whitelisted router addresses
 * @param routerRecipients - Mapping of router withdraw recipient addresses.
 * If set, all liquidity is withdrawn only to this address. Must be set by routerOwner
 * (if configured) or the router itself
 * @param routerOwners - Mapping of router owners
 * If set, can update the routerRecipient
 * @param proposedRouterOwners - Mapping of proposed router owners
 * Must wait timeout to set the
 * @param proposedRouterTimestamp - Mapping of proposed router owners timestamps
 * When accepting a proposed owner, must wait for delay to elapse
 */
struct RouterPermissionsManagerInfo {
  mapping(address => bool) approvedRouters;
  mapping(address => bool) approvedForPortalRouters;
  mapping(address => address) routerRecipients;
  mapping(address => address) routerOwners;
  mapping(address => address) proposedRouterOwners;
  mapping(address => uint256) proposedRouterTimestamp;
}

struct AppStorage {
  //
  // 0
  bool initialized;
  //
  // Connext
  //
  // 1
  uint256 LIQUIDITY_FEE_NUMERATOR;
  /**
   * @notice The local address that is custodying relayer fees
   */
  // 2
  address relayerFeeVault;
  /**
   * @notice Nonce for the contract, used to keep unique transfer ids.
   * @dev Assigned at first interaction (xcall on origin domain).
   */
  // 3
  uint256 nonce;
  /**
   * @notice The domain this contract exists on.
   * @dev Must match the nomad domain, which is distinct from the "chainId".
   */
  // 4
  uint32 domain;
  /**
   * @notice Mapping holding the AMMs for swapping in and out of local assets.
   * @dev Swaps for an adopted asset <> nomad local asset (i.e. POS USDC <> madUSDC on polygon).
   * This mapping is keyed on the hash of the canonical id + domain for local asset.
   */
  // 6
  mapping(bytes32 => IStableSwap) adoptedToLocalPools;
  /**
   * @notice Mapping of whitelisted assets on same domain as contract.
   * @dev Mapping is keyed on the hash of the canonical id and domain
   */
  // 7
  mapping(bytes32 => bool) approvedAssets;
  /**
   * @notice Mapping of liquidity caps of whitelisted assets. If 0, no cap is enforced.
   * @dev Mapping is keyed on the hash of the canonical id and domain
   */
  // 7
  mapping(bytes32 => uint256) caps;
  /**
   * @notice Mapping of adopted to canonical asset information.
   * @dev If the adopted asset is the native asset, the keyed address will
   * be the wrapped asset address.
   */
  // 8
  mapping(address => TokenId) adoptedToCanonical;
  /**
   * @notice Mapping of representation to canonical asset information.
   */
  // 9
  mapping(address => TokenId) representationToCanonical;
  /**
   * @notice Mapping of hash(canonicalId, canonicalDomain) to adopted asset on this domain.
   * @dev If the adopted asset is the native asset, the stored address will be the
   * wrapped asset address.
   */
  // 10
  mapping(bytes32 => address) canonicalToAdopted;
  /**
   * @notice Mapping of canonical to representation asset information.
   * @dev If the token is of local origin (meaning it was originanlly deployed on this chain),
   * this MUST map to address(0).
   */
  // 11
  mapping(bytes32 => address) canonicalToRepresentation;
  /**
   * @notice Mapping to track transfer status on destination domain
   */
  // 12
  mapping(bytes32 => DestinationTransferStatus) transferStatus;
  /**
   * @notice Mapping holding router address that provided fast liquidity.
   */
  // 13
  mapping(bytes32 => address[]) routedTransfers;
  /**
   * @notice Mapping of router to available balance of an asset.
   * @dev Routers should always store liquidity that they can expect to receive via the bridge on
   * this domain (the nomad local asset).
   */
  // 14
  mapping(address => mapping(address => uint256)) routerBalances;
  /**
   * @notice Mapping of approved relayers
   * @dev Send relayer fee if msg.sender is approvedRelayer; otherwise revert.
   */
  // 15
  mapping(address => bool) approvedRelayers;
  /**
   * @notice The max amount of routers a payment can be routed through.
   */
  // 18
  uint256 maxRoutersPerTransfer;
  /**
   * @notice Stores a mapping of transfer id to slippage overrides.
   */
  // 20
  mapping(bytes32 => uint256) slippage;
  /**
   * @notice Stores a mapping of remote routers keyed on domains.
   * @dev Addresses are cast to bytes32.
   * This mapping is required because the Connext now contains the BridgeRouter and must implement
   * the remotes interface.
   */
  // 21
  mapping(uint32 => bytes32) remotes;
  //
  // ProposedOwnable
  //
  // 22
  address _proposed;
  // 23
  uint256 _proposedOwnershipTimestamp;
  // 24
  bool _routerWhitelistRemoved;
  // 25
  uint256 _routerWhitelistTimestamp;
  // 26
  bool _assetWhitelistRemoved;
  // 27
  uint256 _assetWhitelistTimestamp;
  /**
   * @notice Stores a mapping of address to Roles
   * @dev returns uint representing the enum Role value
   */
  // 28
  mapping(address => Role) roles;
  //
  // RouterFacet
  //
  // 29
  RouterPermissionsManagerInfo routerPermissionInfo;
  //
  // ReentrancyGuard
  //
  // 30
  uint256 _status;
  //
  // StableSwap
  //
  /**
   * @notice Mapping holding the AMM storages for swapping in and out of local assets
   * @dev Swaps for an adopted asset <> nomad local asset (i.e. POS USDC <> madUSDC on polygon)
   * Struct storing data responsible for automatic market maker functionalities. In order to
   * access this data, this contract uses SwapUtils library. For more details, see SwapUtils.sol.
   */
  // 31
  mapping(bytes32 => SwapUtils.Swap) swapStorages;
  /**
   * @notice Maps token address to an index in the pool. Used to prevent duplicate tokens in the pool.
   * @dev getTokenIndex function also relies on this mapping to retrieve token index.
   */
  // 32
  mapping(bytes32 => mapping(address => uint8)) tokenIndexes;
  /**
   * @notice Stores whether or not bribing, AMMs, have been paused.
   */
  // 33
  bool _paused;
  //
  // AavePortals
  //
  /**
   * @notice Address of Aave Pool contract.
   */
  // 34
  address aavePool;
  /**
   * @notice Fee percentage numerator for using Portal liquidity.
   * @dev Assumes the same basis points as the liquidity fee.
   */
  // 35
  uint256 aavePortalFeeNumerator;
  /**
   * @notice Mapping to store the transfer liquidity amount provided by Aave Portals.
   */
  // 36
  mapping(bytes32 => uint256) portalDebt;
  /**
   * @notice Mapping to store the transfer liquidity amount provided by Aave Portals.
   */
  // 37
  mapping(bytes32 => uint256) portalFeeDebt;
  /**
   * @notice Mapping of approved sequencers
   * @dev Sequencer address provided must belong to an approved sequencer in order to call `execute`
   * for the fast liquidity route.
   */
  // 38
  mapping(address => bool) approvedSequencers;
  /**
   * @notice Remote connection manager for xapp.
   */
  // 39
  IConnectorManager xAppConnectionManager;
}

library LibConnextStorage {
  function connextStorage() internal pure returns (AppStorage storage ds) {
    assembly {
      ds.slot := 0
    }
  }
}

