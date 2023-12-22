// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./ITradingCore.sol";
import "./IMarketBook.sol";
import "./Errors.sol";
import "./ERC20Fixed.sol";
import "./Allowlistable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ERC20.sol";
import "./SafeCast.sol";

contract MarketBook is
  IMarketBook,
  OwnableUpgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable,
  Allowlistable
{
  using ERC20Fixed for ERC20;
  using SafeCast for uint256;

  address baseToken;
  ITradingCore tradingCore;
  IRegistryCore registry;
  AbstractOracleAggregator oracleAggregator;

  uint32 expiryBlocks;

  mapping(bytes32 => OpenTradeInput)
    internal _openPendingMarketOrderByOrderHash;
  mapping(bytes32 => uint64) internal _openBlockByOrderHash;

  event SetExpiryBlocksEvent(uint256 expiryBlocks);

  function initialize(
    address _owner,
    ITradingCore _tradingCore,
    IRegistryCore _registryCore,
    uint32 _expiryBlocks
  ) external initializer {
    __Ownable_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __Allowlistable_init();
    _transferOwnership(_owner);
    tradingCore = _tradingCore;
    baseToken = address(tradingCore.baseToken());
    registry = _registryCore;
    oracleAggregator = tradingCore.oracleAggregator();
    expiryBlocks = _expiryBlocks;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  modifier onlyLiquidator() {
    _require(registry.isLiquidator(msg.sender), Errors.LIQUIDATOR_ONLY);
    _;
  }

  modifier onlyApprovedPriceId(bytes32 priceId) {
    _require(registry.approvedPriceId(priceId), Errors.APPROVED_PRICE_ID_ONLY);
    _;
  }

  modifier notContract() {
    require(tx.origin == msg.sender);
    _;
  }

  // governance functions

  function onAllowlist() external onlyOwner {
    _onAllowlist();
  }

  function offAllowlist() external onlyOwner {
    _offAllowlist();
  }

  function addAllowlist(address[] memory _allowed) external onlyOwner {
    _addAllowlist(_allowed);
  }

  function removeAllowlist(address[] memory _removed) external onlyOwner {
    _removeAllowlist(_removed);
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  function setExpiryBlocks(uint32 _expiryBlocks) external onlyOwner {
    expiryBlocks = _expiryBlocks;
    emit SetExpiryBlocksEvent(expiryBlocks);
  }

  // external functions

  function openPendingMarketOrder(
    OpenTradeInput calldata openData
  )
    external
    whenNotPaused
    onlyApprovedPriceId(openData.priceId)
    nonReentrant
    onlyAllowlisted
    notContract
  {
    _require(msg.sender == openData.user, Errors.USER_SENDER_MISMATCH);
    bytes32 orderHash = keccak256(abi.encode(openData));
    _openPendingMarketOrderByOrderHash[orderHash] = openData;
    _openBlockByOrderHash[orderHash] = uint256(block.number).toUint64();
    emit OpenPendingMarketOrderEvent(msg.sender, orderHash, openData);
  }

  function executePendingMarketOrder(
    bytes32 orderHash,
    bytes[] calldata priceData
  ) external payable override whenNotPaused nonReentrant onlyLiquidator {
    OpenTradeInput memory openData = _openPendingMarketOrderByOrderHash[
      orderHash
    ];
    _require(openData.user != address(0x0), Errors.ORDER_NOT_FOUND);

    ERC20(baseToken).transferFromFixed(
      openData.user,
      address(this),
      openData.margin
    );

    ERC20(baseToken).approveFixed(address(tradingCore), openData.margin);
    uint256 updateFee = oracleAggregator.getUpdateFee(priceData.length);

    bool success = block.number <=
      _openBlockByOrderHash[orderHash] + expiryBlocks;

    bytes memory returndata;
    if (success) {
      (success, returndata) = address(tradingCore).call{value: updateFee}(
        abi.encodeWithSignature(
          "openMarketOrder((bytes32,address,bool,uint128,uint128,uint128,uint128,uint128),bytes[])",
          openData,
          priceData
        )
      );
    }
    if (success) {
      emit ExecutePendingMarketOrderEvent(orderHash);
    } else {
      string memory errValue = "expired or unknown error";
      if (returndata.length > 0) {
        assembly {
          errValue := mload(returndata)
        }
      }
      ERC20(baseToken).approveFixed(address(tradingCore), 0);
      ERC20(baseToken).transferFixed(openData.user, uint256(openData.margin));
      emit FailedExecutePendingMarketOrderEvent(orderHash, errValue);
    }
    delete _openPendingMarketOrderByOrderHash[orderHash];
    delete _openBlockByOrderHash[orderHash];
  }
}

