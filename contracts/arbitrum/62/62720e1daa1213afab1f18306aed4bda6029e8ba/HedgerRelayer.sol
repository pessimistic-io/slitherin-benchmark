// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16;

import {GelatoRelayContext} from "./GelatoRelayContext.sol";

import {Address} from "./Address.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {Ownable} from "./Ownable.sol";
import {NATIVE_TOKEN} from "./constants_Tokens.sol";

contract HedgerRelayer is GelatoRelayContext, Ownable {
  using Address for address payable;
  using SafeERC20 for IERC20;

  address public masterAgreement;

  receive() external payable {}

  modifier onlyOwnerOrGelato() {
    require(msg.sender == owner() || _isGelatoRelay(msg.sender), "Only owner or Gelato");
    _;
  }

  constructor(address _masterAgreement) {
    masterAgreement = _masterAgreement;
  }

  function setMasterAgreement(address _masterAgreement) external onlyOwner {
    masterAgreement = _masterAgreement;
  }

  function callMasterAgreement(bytes calldata _data) external onlyOwnerOrGelato {
    // Pay Gelato
    _transferRelayFee();
    // Execute
    (bool success, ) = masterAgreement.call(_data);
    require(success, "MasterAgreement call failed");
  }

  function withdrawETH() external onlyOwner {
    uint256 balance = address(this).balance;
    (bool success, ) = payable(owner()).call{value: balance}("");
    require(success, "Failed to send Ether");
  }
}

