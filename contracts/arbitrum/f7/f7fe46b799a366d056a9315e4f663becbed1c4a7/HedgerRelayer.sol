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
  address public collateral;

  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}

  modifier onlyOwnerOrGelato() {
    require(msg.sender == owner() || _isGelatoRelay(msg.sender), "Only owner or Gelato");
    _;
  }

  constructor(address _masterAgreement, address _collateral) {
    masterAgreement = _masterAgreement;
    collateral = _collateral;
    approveMasterAgreement();
  }

  function setMasterAgreement(address _masterAgreement) external onlyOwner {
    masterAgreement = _masterAgreement;
    approveMasterAgreement();
  }

  function setCollateral(address _collateral) external onlyOwner {
    collateral = _collateral;
    approveMasterAgreement();
  }

  function approveMasterAgreement() public onlyOwner {
    IERC20(collateral).safeApprove(masterAgreement, type(uint256).max);
  }

  function callMasterAgreement(bytes calldata _data) public onlyOwner {
    (bool success, ) = masterAgreement.call(_data);
    require(success, "MasterAgreement call failed");
  }

  function callMasterAgreementGelato(bytes calldata _data) external onlyGelatoRelay {
    require(tx.origin == owner(), "Access denied");

    // Pay Gelato
    _transferRelayFee();

    // Execute
    callMasterAgreement(_data);
  }

  function withdrawETH() external onlyOwner {
    uint256 balance = address(this).balance;
    (bool success, ) = payable(owner()).call{value: balance}("");
    require(success, "Failed to send Ether");
  }
}

