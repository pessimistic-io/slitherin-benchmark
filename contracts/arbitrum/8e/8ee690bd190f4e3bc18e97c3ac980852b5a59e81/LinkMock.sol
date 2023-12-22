// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC677Receiver.sol";

// lift up this zeppelin util for use in our tests
contract LinkMock is ERC20 {
  event Transfer(
    address indexed from,
    address indexed to,
    uint256 value,
    bytes data
  );

  function mint(address account, uint256 amount) external virtual {
    _mint(account, amount);
  }

  constructor(string memory name_, string memory symbol_)
    ERC20(name_, symbol_)
  {}

  //ERC677 functions

  /**
   * @dev transfer token to a contract address with additional data if the recipient is a contact.
   * @param _to The address to transfer to.
   * @param _value The amount to be transferred.
   * @param _data The extra data to be passed to the receiving contract.
   */
  function transferAndCall(
    address _to,
    uint256 _value,
    bytes memory _data
  ) public returns (bool success) {
    super.transfer(_to, _value);
    emit Transfer(msg.sender, _to, _value, _data);
    if (_isContract(_to)) {
      _contractFallback(_to, _value, _data);
    }
    return true;
  }

  // PRIVATE

  function _contractFallback(
    address _to,
    uint256 _value,
    bytes memory _data
  ) private {
    IERC677Receiver receiver = IERC677Receiver(_to);
    receiver.onTokenTransfer(msg.sender, _value, _data);
  }

  function _isContract(address _addr) private view returns (bool hasCode) {
    uint256 length;
    assembly {
      length := extcodesize(_addr)
    }
    return length > 0;
  }
}

