// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./Ownable.sol";
import "./Pausable.sol";

interface IERC20 {
  function transfer(address to, uint256 value) external returns (bool);

  function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract Disperse2 is Ownable, Pausable {
  IERC20 public constant sGLP = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);
  address public constant MULTISIG = 0xbc03C6f5C2186cd6fDeED8D9eb3228dAb680ACAE;

  mapping(address => bool) public claimed;
  mapping(address => uint256) public reimbursement;

  constructor() {
    _pause();
  }

  function claim() external whenNotPaused {
    require(tx.origin == msg.sender, '!eoa');
    require(claimed[msg.sender] == false, 'claimed');
    claimed[msg.sender] = true;
    require(sGLP.transferFrom(MULTISIG, msg.sender, reimbursement[msg.sender]), 'fail');
  }

  function setPause(bool _paused) external onlyOwner {
    if (_paused) {
      _pause();
    } else {
      _unpause();
    }
  }

  function updateStorage(
    address[] calldata recipients,
    uint256[] calldata values
  ) external onlyOwner {
    for (uint256 i = 0; i < recipients.length; i = _unsafeInc(i)) {
      reimbursement[recipients[i]] = values[i];
    }
  }

  function _unsafeInc(uint256 x) private pure returns (uint256) {
    unchecked {
      return x + 1;
    }
  }
}

