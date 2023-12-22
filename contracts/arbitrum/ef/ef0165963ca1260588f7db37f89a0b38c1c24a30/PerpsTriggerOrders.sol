// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./IERC721.sol";

contract PerpsTriggerOrders {
  IERC721 public pfydf;
  uint8 public maxTriggerOrders = 2;

  struct TriggerOrder {
    uint256 idxPriceCurrent;
    uint256 idxPriceTarget;
  }

  // tokenId => orders
  mapping(uint256 => TriggerOrder[]) public triggerOrders;

  modifier onlyPositionOwner(uint256 _tokenId) {
    require(msg.sender == pfydf.ownerOf(_tokenId), 'UNAUTHORIZED');
    _;
  }

  function getAllPositionTriggerOrders(uint256 _tokenId)
    external
    view
    returns (TriggerOrder[] memory)
  {
    return triggerOrders[_tokenId];
  }

  function addTriggerOrder(
    uint256 _tokenId,
    uint256 _idxPriceTarget,
    uint256 _currentPrice
  ) external onlyPositionOwner(_tokenId) {
    _addTriggerOrder(_tokenId, _idxPriceTarget, _currentPrice);
  }

  function updateTriggerOrder(
    uint256 _tokenId,
    uint256 _idx,
    uint256 _idxPriceTarget
  ) external onlyPositionOwner(_tokenId) {
    _updateTriggerOrder(_tokenId, _idx, _idxPriceTarget);
  }

  function removeTriggerOrder(uint256 _tokenId, uint256 _idx)
    external
    onlyPositionOwner(_tokenId)
  {
    _removeTriggerOrder(_tokenId, _idx);
  }

  function _addTriggerOrder(
    uint256 _tokenId,
    uint256 _idxPriceTarget,
    uint256 _idxCurrentPrice
  ) internal {
    require(_idxPriceTarget > 0, 'TO0');
    require(triggerOrders[_tokenId].length < maxTriggerOrders, 'TO1');
    require(_idxCurrentPrice != _idxPriceTarget, 'TO2');

    triggerOrders[_tokenId].push(
      TriggerOrder({
        idxPriceCurrent: _idxCurrentPrice,
        idxPriceTarget: _idxPriceTarget
      })
    );
  }

  function _updateTriggerOrder(
    uint256 _tokenId,
    uint256 _idx,
    uint256 _idxTargetPrice
  ) internal {
    require(_idxTargetPrice > 0, 'TO0');

    TriggerOrder storage _order = triggerOrders[_tokenId][_idx];
    bool _isTargetLess = _order.idxPriceTarget < _order.idxPriceCurrent;
    // if original target is less than original current, new target must
    // remain less than, or vice versa for higher than prices
    require(
      _isTargetLess
        ? _idxTargetPrice < _order.idxPriceCurrent
        : _idxTargetPrice > _order.idxPriceCurrent,
      'TO3'
    );
    _order.idxPriceTarget = _idxTargetPrice;
  }

  function _removeTriggerOrder(uint256 _tokenId, uint256 _idx) internal {
    triggerOrders[_tokenId][_idx] = triggerOrders[_tokenId][
      triggerOrders[_tokenId].length - 1
    ];
    triggerOrders[_tokenId].pop();
  }

  function _setPfydf(IERC721 _nft) internal {
    pfydf = _nft;
  }
}

