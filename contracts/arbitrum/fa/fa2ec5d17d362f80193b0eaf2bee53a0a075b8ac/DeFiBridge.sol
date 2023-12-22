// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./AccessControl.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./IWormhole.sol";
import "./IWormholeRelayer.sol";
import "./IDeFiBridge.sol";

contract DeFiBridge is Pausable, AccessControl, ReentrancyGuard, IDeFiBridge {
  using SafeERC20 for IERC20;

  uint256 public constant GAS_LIMIT = 250_000;
  uint256 public constant PRECISION = 10 ** 3;

  uint16 private _counter;
  uint16 private _chain;
  mapping(uint16 => Chain) private _chains;
  mapping(bytes32 => bool) private _seenDeliveryVaaHashes;
  uint256 private _nativeFee;     // native coin fee(absolute)
  uint256 private _tokenFee;      // token fee(percentage)
  uint256 private _minTokenFee;   // min token fee
  uint256 private _maxTokenFee;   // max token fee

  IWormholeRelayer private _relayer;
  IWormhole private _wormhole;
  address private _wallet;

  constructor(uint16 chain_, address wormhole_, address relayer_, address wallet_) {
    if (chain_ == 0) revert ChainZeroErr();
    if (wormhole_ == address(0)) revert WormholeNullAddressErr();
    if (relayer_ == address(0)) revert RelayertNullAddressErr();
    if (wallet_ == address(0)) revert WalletNullAddressErr();

    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

    _chain = chain_;
    _wormhole = IWormhole(wormhole_);
    _relayer = IWormholeRelayer(relayer_);
    _wallet = wallet_;
  }

  modifier onlyWormholeRelayer() {
    if (_msgSender() != address(_relayer)) revert RelayertAuthErr();
    _;
  }

  modifier onlyRegisteredSender(uint16 chain_, bytes32 sender_) {
    if (!_chains[chain_].enabled || _chains[chain_].sender != sender_) revert SenderAuthErr();
    _;
  }

  receive()
    external
    payable 
  {
    // solhint-disable-previous-line no-empty-blocks
  }

  function setupBridge(uint16 chain_, address wormhole_, address relayer_)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (chain_ == 0) revert ChainZeroErr();
    if (wormhole_ == address(0)) revert WormholeNullAddressErr();
    if (relayer_ == address(0)) revert RelayertNullAddressErr();

    _chain = chain_;
    _wormhole = IWormhole(wormhole_);
    _relayer = IWormholeRelayer(relayer_);

    emit BridgeSetup(wormhole_, relayer_);
  }

  function setupWallet(address wallet_)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (wallet_ == address(0)) revert WalletNullAddressErr();

    _wallet = wallet_;

    emit WalletSetup(wallet_);
  }

  function setupFees(uint256 nativeFee_, uint256 tokenFee_, uint256 minTokenFee_, uint256 maxTokenFee_)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (tokenFee_ > PRECISION) revert MaxTokenFeeErr(tokenFee_);
    if (minTokenFee_ > maxTokenFee_) revert MinMaxTokenFeeErr(minTokenFee_, maxTokenFee_);

    _nativeFee = nativeFee_;
    _tokenFee = tokenFee_;
    _minTokenFee = minTokenFee_;
    _maxTokenFee = maxTokenFee_;

    emit FeesSetup(nativeFee_, tokenFee_);
  }

  function setupChain(uint16 chain_, address pool_, address defi_)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (pool_ == address(0)) revert PoolNullAddressErr();
    if (defi_ == address(0)) revert DefiNullAddressErr();

    _chains[chain_].defined = true;
    _chains[chain_].pool = pool_;
    _chains[chain_].defi = defi_;
    _chains[chain_].sender = bytes32(uint256(uint160(pool_)));
    _chains[chain_].enabled = true;

    emit ChainAdded(chain_, pool_, defi_, true);
  }

  function enableChain(uint16 chain_)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (!_chains[chain_].defined) revert ChainUndefinedErr(chain_);

    _chains[chain_].enabled = true;

    emit ChainUpdated(chain_, _chains[chain_].pool, _chains[chain_].defi, true);
  }

  function disableChain(uint16 chain_)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (!_chains[chain_].defined) revert ChainUndefinedErr(chain_);

    _chains[chain_].enabled = false;

    emit ChainUpdated(chain_, _chains[chain_].pool, _chains[chain_].defi, false);
  }

  function bridge(uint16 chain_, address recipient_, uint256 amount_)
    external
    payable
    nonReentrant
    whenNotPaused
    returns (bytes memory msgHash)
  {
    if (_chain == chain_) revert ChainDuplicateErr();

    (uint256 nativeFee, uint256 tokenFee) = getFees(chain_, amount_);    
    if (msg.value < nativeFee) revert NativeFeeErr(nativeFee, msg.value);
    
    Chain memory destChain = _chains[chain_];
    if (!destChain.enabled) revert ChainDisabledErr(chain_);
    
    Chain memory sourceChain = _chains[_chain];
    uint256 nativeCost = nativeFee - _nativeFee;
    uint256 tokenCost = amount_ - tokenFee;
    
    IERC20(sourceChain.defi).safeTransferFrom(_msgSender(), address(this), tokenCost);
    if (tokenFee > 0) {
      IERC20(sourceChain.defi).safeTransferFrom(_msgSender(), _wallet, tokenFee);
    }
    if (_nativeFee > 0) {
      (bool successF, ) = _wallet.call{value: _nativeFee}('');
      if (!successF) revert NativeFeeTransferErr();
    }
    
    _counter++;
    msgHash = abi.encode(_msgSender(), _counter);
    bytes memory payload = abi.encode(recipient_, tokenCost, msgHash);
    _relayer.sendPayloadToEvm{value: nativeCost}(chain_, destChain.pool, payload, 0, GAS_LIMIT);

    uint256 refund = msg.value - nativeFee;
    if (refund > 0) {
      (bool successR, ) = _msgSender().call{value: refund}('');
      if (!successR) revert NativeRefundTransferErr();
    }

    emit Deposited(msgHash, chain_, recipient_, amount_);
  }

  function receiveWormholeMessages(
    bytes memory payload,
    bytes[] memory,
    bytes32 sourceAddress,
    uint16 sourceChain,
    bytes32 deliveryHash
  )
    public payable override
    whenNotPaused
    onlyWormholeRelayer
    onlyRegisteredSender(sourceChain, sourceAddress)
  {
    // Ensure no duplicate deliveries
    if (_seenDeliveryVaaHashes[deliveryHash]) revert MsgDuplicateErr(deliveryHash);
    _seenDeliveryVaaHashes[deliveryHash] = true;

    // Parse the payload and do the corresponding actions!
    (address recipient, uint256 amount, bytes memory msgHash) = abi.decode(payload, (address, uint256, bytes));
    Chain memory chain = _chains[_chain];

    IERC20(chain.defi).safeTransfer(recipient, amount);

    emit Withdrawn(msgHash, sourceChain, recipient, amount);
  }

  function recoverNative()
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {    
    uint256 balance = address(this).balance;

    (bool success, ) = _msgSender().call{value: balance}('');
    if (!success) revert NativeTransferErr();

    emit NativeRecovered(balance);
  }

  function recoverERC20(address token_, uint256 amount_)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    IERC20(token_).safeTransfer(_msgSender(), amount_);

    emit ERC20Recovered(token_, amount_);
  }

  function getFees(uint16 chain_, uint256 amount_)
    public
    view
    returns(uint256 nativeCost, uint256 tokenCost)
  {
    uint256 deliveryCost;
    (deliveryCost, ) = _relayer.quoteEVMDeliveryPrice(chain_, 0, GAS_LIMIT);
    nativeCost = _wormhole.messageFee() + deliveryCost + _nativeFee;

    if (_tokenFee > 0) {
      tokenCost = amount_ * PRECISION / _tokenFee;
    }
    if (tokenCost < _minTokenFee) {
      tokenCost = _minTokenFee;
    } else if (tokenCost > _maxTokenFee) {
      tokenCost = _maxTokenFee;
    }
  }

  function getWallet()
    external
    view
    returns(address)
  {
    return _wallet;
  }

  function getFeesInfo()
    external
    view
    returns(uint256 nativeFee, uint256 tokenFee, uint256 minTokenFee, uint256 maxTokenFee)
  {
    nativeFee = _nativeFee;
    tokenFee = _tokenFee;
    minTokenFee = _minTokenFee;
    maxTokenFee = _maxTokenFee;
  }

  function getChain(uint16 chain_)
    public
    view
    returns(Chain memory)
  {
    return _chains[chain_];
  }
}

