// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

interface INftPacks {
    function open(
    uint256 _optionId,
    address _toAddress,
    uint256 _amount
  ) external;
}
