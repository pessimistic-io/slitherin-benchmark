pragma solidity 0.8.6;

import "./ArbGasInfo.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";
import "./ConfirmedOwner.sol";
import "./ExecutionPrevention.sol";
import "./AggregatorV3Interface.sol";
import "./LinkTokenInterface.sol";
import "./KeeperCompatibleInterface.sol";
import "./OptimismGasInterface.sol";
import {Config, State} from "./KeeperRegistryInterface.sol";

/**
 * @notice Base Keeper Registry contract, contains shared logic between
 * KeeperRegistry and KeeperRegistryLogic
 */
abstract contract KeeperRegistryBase is ConfirmedOwner, ExecutionPrevention, ReentrancyGuard, Pausable {
  address internal constant ZERO_ADDRESS = address(0);
  address internal constant IGNORE_ADDRESS = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
  bytes4 internal constant CHECK_SELECTOR = KeeperCompatibleInterface.checkUpkeep.selector;
  bytes4 internal constant PERFORM_SELECTOR = KeeperCompatibleInterface.performUpkeep.selector;
  uint256 internal constant PERFORM_GAS_MIN = 2_300;
  uint256 internal constant CANCELLATION_DELAY = 50;
  uint256 internal constant PERFORM_GAS_CUSHION = 5_000;
  uint256 public REGISTRY_GAS_OVERHEAD = 80_000;
  uint256 internal constant PPB_BASE = 1_000_000_000;
  uint64 internal constant UINT64_MAX = 2**64 - 1;
  uint96 internal constant LINK_TOTAL_SUPPLY = 1e27;
  bytes17 public L1_FEE_DATA_PADDING = 0xffffffffffffffffffffffffffffffffff;
  bytes4 public PERFORM_DATA_PADDING = 0xffffffff;
  bytes32 public ESTIMATED_MSG_DATA = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

  uint256 public s_gasLimit;
  uint256 public s_l1;
  uint256 public s_l1GasWei;
  uint256 public s_l1CostWei;
  uint256 public s_l1CostWei2;
  uint256 public s_l2;
  uint256 public s_gasWei;
  uint256 public s_weiForGas;
  uint256 public s_linkEth;

  address[] internal s_keeperList;
  EnumerableSet.UintSet internal s_upkeepIDs;
  mapping(uint256 => Upkeep) internal s_upkeep;
  mapping(address => KeeperInfo) internal s_keeperInfo;
  mapping(address => address) internal s_proposedPayee;
  mapping(uint256 => bytes) internal s_checkData;
  mapping(address => MigrationPermission) internal s_peerRegistryMigrationPermission;
  Storage internal s_storage;
  uint256 internal s_fallbackGasPrice; // not in config object for gas savings
  uint256 internal s_fallbackLinkPrice; // not in config object for gas savings
  uint96 internal s_ownerLinkBalance;
  uint256 internal s_expectedLinkBalance;
  address internal s_transcoder;
  address internal s_registrar;

  LinkTokenInterface public immutable LINK;
  AggregatorV3Interface public immutable LINK_ETH_FEED;
  AggregatorV3Interface public immutable FAST_GAS_FEED;
  OptimismGasInterface public immutable OPTIMISM_ORACLE =
    OptimismGasInterface(0x420000000000000000000000000000000000000F);
  ArbGasInfo public immutable ARBITRUM_ORACLE = ArbGasInfo(0x000000000000000000000000000000000000006C);
  PaymentModel public immutable PAYMENT_MODEL;

  error CannotCancel();
  error UpkeepNotActive();
  error MigrationNotPermitted();
  error UpkeepNotCanceled();
  error UpkeepNotNeeded();
  error NotAContract();
  error PaymentGreaterThanAllLINK();
  error OnlyActiveKeepers();
  error InsufficientFunds();
  error KeepersMustTakeTurns();
  error ParameterLengthError();
  error OnlyCallableByOwnerOrAdmin();
  error OnlyCallableByLINKToken();
  error InvalidPayee();
  error DuplicateEntry();
  error ValueNotChanged();
  error IndexOutOfRange();
  error TranscoderNotSet();
  error ArrayHasNoEntries();
  error GasLimitOutsideRange();
  error OnlyCallableByPayee();
  error OnlyCallableByProposedPayee();
  error GasLimitCanOnlyIncrease();
  error OnlyCallableByAdmin();
  error OnlyCallableByOwnerOrRegistrar();
  error InvalidRecipient();
  error InvalidDataLength();
  error TargetCheckReverted(bytes reason);

  enum MigrationPermission {
    NONE,
    OUTGOING,
    INCOMING,
    BIDIRECTIONAL
  }

  enum PaymentModel {
    DEFAULT,
    ARBITRUM,
    OPTIMISM
  }

  /**
   * @notice storage of the registry, contains a mix of config and state data
   */
  struct Storage {
    uint32 paymentPremiumPPB;
    uint32 flatFeeMicroLink;
    uint24 blockCountPerTurn;
    uint32 checkGasLimit;
    uint24 stalenessSeconds;
    uint16 gasCeilingMultiplier;
    uint96 minUpkeepSpend; // 1 full evm word
    uint32 maxPerformGas;
    uint32 nonce;
  }

  struct Upkeep {
    uint96 balance;
    address lastKeeper; // 1 full evm word
    uint32 executeGas;
    uint64 maxValidBlocknumber;
    address target; // 2 full evm words
    uint96 amountSpent;
    address admin; // 3 full evm words
  }

  struct KeeperInfo {
    address payee;
    uint96 balance;
    bool active;
  }

  struct PerformParams {
    address from;
    uint256 id;
    bytes performData;
    uint256 maxLinkPayment;
    uint256 gasLimit;
    uint256 adjustedGasWei;
    uint256 linkEth;
  }

  event UpkeepRegistered(uint256 indexed id, uint32 executeGas, address admin);
  event UpkeepPerformed(
    uint256 indexed id,
    bool indexed success,
    address indexed from,
    uint96 payment,
    bytes performData
  );
  event UpkeepCanceled(uint256 indexed id, uint64 indexed atBlockHeight);
  event FundsAdded(uint256 indexed id, address indexed from, uint96 amount);
  event FundsWithdrawn(uint256 indexed id, uint256 amount, address to);
  event OwnerFundsWithdrawn(uint96 amount);
  event UpkeepMigrated(uint256 indexed id, uint256 remainingBalance, address destination);
  event UpkeepReceived(uint256 indexed id, uint256 startingBalance, address importedFrom);
  event ConfigSet(Config config);
  event KeepersUpdated(address[] keepers, address[] payees);
  event PaymentWithdrawn(address indexed keeper, uint256 indexed amount, address indexed to, address payee);
  event PayeeshipTransferRequested(address indexed keeper, address indexed from, address indexed to);
  event PayeeshipTransferred(address indexed keeper, address indexed from, address indexed to);
  event UpkeepGasLimitSet(uint256 indexed id, uint96 gasLimit);

  /**
   * @param paymentModel the payment model of default, Arbitrum, or Optimism
   * @param link address of the LINK Token
   * @param linkEthFeed address of the LINK/ETH price feed
   * @param fastGasFeed address of the Fast Gas price feed
   */
  constructor(
    uint8 paymentModel,
    address link,
    address linkEthFeed,
    address fastGasFeed
  ) ConfirmedOwner(msg.sender) {
    PAYMENT_MODEL = PaymentModel(paymentModel);
    LINK = LinkTokenInterface(link);
    LINK_ETH_FEED = AggregatorV3Interface(linkEthFeed);
    FAST_GAS_FEED = AggregatorV3Interface(fastGasFeed);
  }

  /**
   * @dev retrieves feed data for fast gas/eth and link/eth prices. if the feed
   * data is stale it uses the configured fallback price. Once a price is picked
   * for gas it takes the min of gas price in the transaction or the fast gas
   * price in order to reduce costs for the upkeep clients.
   */
  function _getFeedData() internal view returns (uint256 gasWei, uint256 linkEth) {
    uint32 stalenessSeconds = s_storage.stalenessSeconds;
    bool staleFallback = stalenessSeconds > 0;
    uint256 timestamp;
    int256 feedValue;
    (, feedValue, , timestamp, ) = FAST_GAS_FEED.latestRoundData();
    if ((staleFallback && stalenessSeconds < block.timestamp - timestamp) || feedValue <= 0) {
      gasWei = s_fallbackGasPrice;
    } else {
      gasWei = uint256(feedValue);
    }
    (, feedValue, , timestamp, ) = LINK_ETH_FEED.latestRoundData();
    if ((staleFallback && stalenessSeconds < block.timestamp - timestamp) || feedValue <= 0) {
      linkEth = s_fallbackLinkPrice;
    } else {
      linkEth = uint256(feedValue);
    }
    return (gasWei, linkEth);
  }

  /**
   * @dev calculates LINK paid for gas spent plus a configure premium percentage
   */
  function _calculatePaymentAmount(
    uint256 gasLimit,
    uint256 gasWei,
    uint256 linkEth,
    bool isExecution,
    bytes memory data
  ) internal returns (uint96 payment) {
    uint256 weiForGas = gasWei * (gasLimit + REGISTRY_GAS_OVERHEAD);
    uint256 premium = PPB_BASE + s_storage.paymentPremiumPPB;

    uint256 l1CostWei = 0;
    if (PAYMENT_MODEL == PaymentModel.OPTIMISM) {
      l1CostWei = OPTIMISM_ORACLE.getL1Fee(data);
    } else if (PAYMENT_MODEL == PaymentModel.ARBITRUM) {
      (, , , , , uint256 l1GasWei) = ARBITRUM_ORACLE.getPricesInWei();
      s_l1GasWei = l1GasWei;
      l1CostWei = gasLimit * l1GasWei;
      s_l1CostWei2 = ARBITRUM_ORACLE.getCurrentTxL1GasFees();
    }

    uint256 total = ((weiForGas + l1CostWei) * 1e9 * premium) / linkEth + uint256(s_storage.flatFeeMicroLink) * 1e12;

    uint256 l1 = (l1CostWei * 1e9 * premium) / linkEth;
    s_l1 = l1;
    uint256 l2 = (weiForGas * 1e9 * premium) / linkEth;
    s_l2 = l2;
    s_l1CostWei = l1CostWei;
    s_gasWei = gasWei;
    s_linkEth = linkEth;
    s_gasLimit = gasLimit;
    s_weiForGas = weiForGas;

    if (total > LINK_TOTAL_SUPPLY) revert PaymentGreaterThanAllLINK();
    return uint96(total); // LINK_TOTAL_SUPPLY < UINT96_MAX
  }

  /**
   * @dev ensures all required checks are passed before an upkeep is performed
   */
  function _prePerformUpkeep(
    Upkeep memory upkeep,
    address from,
    uint256 maxLinkPayment
  ) internal view {
    if (!s_keeperInfo[from].active) revert OnlyActiveKeepers();
    if (upkeep.balance < maxLinkPayment) revert InsufficientFunds();
    if (upkeep.lastKeeper == from) revert KeepersMustTakeTurns();
  }

  /**
   * @dev adjusts the gas price to min(ceiling, tx.gasprice) or just uses the ceiling if tx.gasprice is disabled
   */
  function _adjustGasPrice(uint256 gasWei, bool isExecution) internal view returns (uint256 adjustedPrice) {
    adjustedPrice = gasWei * s_storage.gasCeilingMultiplier;
    if (isExecution && tx.gasprice < adjustedPrice) {
      adjustedPrice = tx.gasprice;
    }
  }

  /**
   * @dev generates a PerformParams struct for use in _performUpkeepWithParams()
   */
  function _generatePerformParams(
    address from,
    uint256 id,
    bytes memory performData,
    bool isExecution
  ) internal returns (PerformParams memory) {
    uint256 gasLimit = s_upkeep[id].executeGas;
    (uint256 gasWei, uint256 linkEth) = _getFeedData();
    uint256 adjustedGasWei = _adjustGasPrice(gasWei, isExecution);
    //uint256 l1CostWei = 0;
    bytes memory data = new bytes(0);
    if (PAYMENT_MODEL == PaymentModel.OPTIMISM) {
      if (isExecution) {
        data = bytes.concat(msg.data, L1_FEE_DATA_PADDING);
      } else {
        data = bytes.concat(performData, PERFORM_DATA_PADDING);
        data = bytes.concat(data, L1_FEE_DATA_PADDING);
      }
      //l1CostWei = OPTIMISM_ORACLE.getL1Fee(data);
    } else if (PAYMENT_MODEL == PaymentModel.ARBITRUM) {
      //      if (isExecution) {
      //        l1CostWei = ARBITRUM_ORACLE.getCurrentTxL1GasFees();
      //      } else {
      //        (, , , , , uint256 l1GasWei) = ARBITRUM_ORACLE.getPricesInWei();
      //        l1CostWei = gasLimit * l1GasWei;
      //      }
    }
    uint96 maxLinkPayment = _calculatePaymentAmount(gasLimit, adjustedGasWei, linkEth, isExecution, data);

    return
      PerformParams({
        from: from,
        id: id,
        performData: performData,
        maxLinkPayment: maxLinkPayment,
        gasLimit: gasLimit,
        adjustedGasWei: adjustedGasWei,
        linkEth: linkEth
      });
  }
}

