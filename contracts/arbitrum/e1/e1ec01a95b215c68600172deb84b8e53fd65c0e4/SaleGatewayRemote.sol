// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./NonblockingLzAppUpgradeable.sol";
import "./AdminProxyManager.sol";
import "./IGovFactory.sol";
import "./ISaleGatewayRemote.sol";

contract SaleGatewayRemote is
  Initializable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  NonblockingLzAppUpgradeable,
  PausableUpgradeable,
  AdminProxyManager,
  ISaleGatewayRemote
{
  uint256 public override gasForDestinationLzReceive;
  uint256 public override crossFee_d2;

  IGovFactory public factory;

  struct DstChain {
    uint240 chainID;
    uint16 lzChainID;
    address saleGateway;
  }

  DstChain public override dstChain; // dst chain supported

  event BuyToken(address sale, uint240 dstChainID, uint16 dstLzChainID, address dstSaleGateway, bytes dstPayload);

  function init(
    address _endpoint,
    uint256 _gasForDestinationLzReceive,
    uint256 _crossFee_d2
  ) external initializer proxied {
    __UUPSUpgradeable_init();
    __Pausable_init();
    __ReentrancyGuard_init();
    __NonblockingLzAppUpgradeable_init(_endpoint); // layer zero endpoint
    __AdminProxyManager_init(_msgSender());

    gasForDestinationLzReceive = _gasForDestinationLzReceive;
    crossFee_d2 = _crossFee_d2;
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override proxied {}

  function setRemote(uint240 _chainID, uint16 _lzChainID, address _saleGateway) external virtual onlyOwner {
    require(_saleGateway != address(0) && _chainID != uint240(block.chainid) && _lzChainID > 0, 'bad');

    dstChain = DstChain({chainID: _chainID, lzChainID: _lzChainID, saleGateway: _saleGateway});

    this.setTrustedRemoteAddress(_lzChainID, abi.encodePacked(_saleGateway));
  }

  /**
   * @dev Buy token project using token raise
   */
  function buyToken(
    bytes calldata _payload,
    uint256 _tax
  ) external payable virtual override whenNotPaused nonReentrant {
    require(address(factory) != address(0) && factory.isKnown(_msgSender()), 'unknown');

    uint256 feeIn = msg.value;
    if (_tax > 0) feeIn -= _tax;

    DstChain memory dst = dstChain;

    _lzSend(dst.lzChainID, _payload, payable(address(this)), address(0x0), adapterParams(), feeIn); // send LayerZero message

    emit BuyToken(_msgSender(), dst.chainID, dst.lzChainID, dst.saleGateway, _payload);
  }

  /**
   * @dev Toggle buyToken pause
   */
  function togglePause() external virtual onlyOwner {
    if (paused()) {
      _unpause();
    } else {
      _pause();
    }
  }

  function estimateFees(bytes calldata _payload) external view virtual override returns (uint256 fees) {
    (fees, ) = lzEndpoint.estimateFees(dstChain.lzChainID, address(this), _payload, false, adapterParams());
  }

  function adapterParams() internal view virtual returns (bytes memory) {
    uint16 version = 1;
    return abi.encodePacked(version, gasForDestinationLzReceive);
  }

  /**
   * @dev Withdraw eth
   */
  function wdEth(uint256 _amount, address payable _target) external virtual onlyOwner nonReentrant {
    if (address(this).balance < _amount) _amount = address(this).balance;

    (bool success, ) = _target.call{value: _amount}('');
    require(success, 'bad');
  }

  /**
   * @dev Set gas for destination layerZero receive
   * @param _gasForDestinationLzReceive Sale implementation address
   */
  function setGasForDestinationLzReceive(uint256 _gasForDestinationLzReceive) external virtual onlyOwner {
    require(_gasForDestinationLzReceive > 0 && gasForDestinationLzReceive != _gasForDestinationLzReceive, 'bad');

    gasForDestinationLzReceive = _gasForDestinationLzReceive;
  }

  /**
   * @dev Set cross fee
   * @param _crossFee_d2 Cross fee in 2 decimal
   */
  function setCrossFee_d2(uint256 _crossFee_d2) external virtual onlyOwner {
    require(crossFee_d2 != _crossFee_d2, 'bad');

    crossFee_d2 = _crossFee_d2;
  }

  function setFactory(address _factory) external virtual onlyOwner {
    require(address(factory) != _factory && _factory != address(0), 'bad');

    factory = IGovFactory(_factory);
  }

  receive() external payable virtual {}

  function _nonblockingLzReceive(
    uint16, // _srcChainId
    bytes memory, // _srcAddress
    uint64, // _nonce
    bytes memory // payload
  ) internal virtual override whenNotPaused {
    revert();
  }
}

