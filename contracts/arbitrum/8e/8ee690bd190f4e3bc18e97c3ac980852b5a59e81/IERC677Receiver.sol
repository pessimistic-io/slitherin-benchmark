pragma solidity ^0.8.0;

interface IERC677Receiver {
  function onTokenTransfer(
    address _sender,
    uint256 _value,
    bytes memory _data
  ) external;
}

