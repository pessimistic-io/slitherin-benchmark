// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20Upgradeable, ERC20Upgradeable} from "./ERC20Upgradeable.sol";
import {IPoolFactory} from "./IPoolFactory.sol";
import {IInterestRateModel} from "./IInterestRateModel.sol";

error AIZ();

/// @notice This contract describes Pool's storage, events and initializer
abstract contract PoolBaseInfo is ERC20Upgradeable {
  /// @notice Address of the pool's manager
  address public manager;

  /// @notice Pool currency token
  IERC20Upgradeable public currency;

  /// @notice PoolFactory contract
  IPoolFactory public factory;

  /// @notice InterestRateModel contract address
  IInterestRateModel public interestRateModel;

  /// @notice Reserve factor as 18-digit decimal
  uint256 public reserveFactor;

  /// @notice Insurance factor as 18-digit decimal
  uint256 public insuranceFactor;

  /// @notice Pool utilization that leads to warning state (as 18-digit decimal)
  uint256 public warningUtilization;

  /// @notice Pool utilization that leads to provisional default (as 18-digit decimal)
  uint256 public provisionalDefaultUtilization;

  /// @notice Grace period for warning state before pool goes to default (in seconds)
  uint256 public warningGracePeriod;

  /// @notice Max period for which pool can stay not active before it can be closed by governor (in seconds)
  uint256 public maxInactivePeriod;

  /// @notice Period after default to start auction after which pool can be closed by anyone (in seconds)
  uint256 public periodToStartAuction;

  enum State {
    Active,
    Warning,
    ProvisionalDefault,
    Default,
    Closed
  }

  /// @notice Indicator if debt has been claimed
  bool public debtClaimed;

  /// @notice Structure describing all pool's borrows details
  struct BorrowInfo {
    uint256 principal;
    uint256 borrows;
    uint256 reserves;
    uint256 insurance;
    uint256 lastAccrual; // timestamp of last accrual
    uint256 enteredProvisionalDefault; // timestamp when pool entered provisional default state
    uint256 enteredZeroUtilization; // timestamp when pool entered zero utilization state
    State state;
  }

  /// @notice Last updated borrow info
  BorrowInfo internal _info;

  /// @notice Pool's symbol
  string internal _symbol;

  // EVENTS

  /// @notice Event emitted when pool is closed
  event Closed();

  /// @notice Event emitted when liquidity is provided to the Pool
  /// @param provider Address who provided liquidity
  /// @param currencyAmount Amount of pool's currency provided
  /// @param tokens Amount of cp-tokens received by provider in response
  event Provided(address indexed provider, uint256 currencyAmount, uint256 tokens);

  /// @notice Event emitted when liquidity is redeemed from the Pool
  /// @param redeemer Address who redeems liquidity
  /// @param currencyAmount Amount of currency received by redeemer
  /// @param tokens Amount of given and burned cp-tokens
  event Redeemed(address indexed redeemer, uint256 currencyAmount, uint256 tokens);

  /// @notice Event emitted when manager assignes liquidity
  /// @param amount Amount of currency borrower
  /// @param receiver Address where borrow has been transferred
  event Borrowed(uint256 amount, address indexed receiver);

  /// @notice Event emitted when manager returns liquidity assignment
  /// @param amount Amount of currency repaid
  event Repaid(uint256 amount);

  /// @notice Event emitted when reserves are transferred to treasury
  /// @param treasury Recipient of the transferred reserves
  /// @param amount Amount transferred
  event ReservesTransferred(address treasury, uint256 amount);

  // CONSTRUCTOR

  /// @notice Upgradeable contract constructor
  /// @param manager_ Address of the Pool's manager
  /// @param currency_ Address of the currency token
  function __PoolBaseInfo_init(
    address manager_,
    IERC20Upgradeable currency_
  ) internal onlyInitializing nonZeroAddress(manager_) nonZeroAddress(address(currency_)) {
    manager = manager_;
    currency = currency_;
    factory = IPoolFactory(msg.sender);

    interestRateModel = IInterestRateModel(factory.interestRateModel());
    (reserveFactor, insuranceFactor, warningUtilization) = (
      factory.reserveFactor(),
      factory.insuranceFactor(),
      factory.warningUtilization()
    );

    provisionalDefaultUtilization = factory.provisionalDefaultUtilization();
    warningGracePeriod = factory.warningGracePeriod();
    maxInactivePeriod = factory.maxInactivePeriod();
    periodToStartAuction = factory.periodToStartAuction();

    _symbol = factory.getPoolSymbol(address(currency), address(manager));
    __ERC20_init(string(bytes.concat(bytes('Pool '), bytes(_symbol))), '');

    (_info.enteredZeroUtilization, _info.lastAccrual) = (block.timestamp, block.timestamp);
  }

  /// @notice Modifier for the functions restricted to pool creator
  modifier nonZeroAddress(address addr) {
    if (addr == address(0)) revert AIZ();
    _;
  }
}

