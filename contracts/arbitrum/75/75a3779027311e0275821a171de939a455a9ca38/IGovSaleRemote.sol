// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IGovSaleRemote {
  function init(
    uint128 _start,
    uint128 _duration,
    uint256 _sale,
    uint256 _price,
    uint256[4] memory _fee_d2,
    address _payment,
    string[3] calldata _nameVersionMsg,
    uint128[2] calldata _voteStartEnd,
    uint128 _dstPaymentDecimals,
    address _targetSale
  ) external;

  function finalize(bytes calldata _salePayload) external;
}

