// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16;

import "./HedgerRelayerBase.sol";
import "./IMasterAgreement.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";

contract HedgerRelayer is HedgerRelayerBase {
  using SafeERC20 for IERC20;

  address public masterAgreement;
  address public collateral;
  string[] public pricingURLs = ["wss://hedger-api.herokuapp.com/v1/quotes"];
  string[] public marketsURLs = ["https://hedger-api.herokuapp.com/v1/info"];

  constructor(
    address _trustedForwarder,
    address _masterAgreement,
    address _collateral
  ) HedgerRelayerBase(_trustedForwarder) {
    masterAgreement = _masterAgreement;
    collateral = _collateral;
    _approveMasterAgreement();
    _enlist();
  }

  function setMasterAgreement(address _masterAgreement) external onlyOwner {
    masterAgreement = _masterAgreement;
    _approveMasterAgreement();
    _enlist();
  }

  function setCollateral(address _collateral) external onlyOwner {
    collateral = _collateral;
    _approveMasterAgreement();
  }

  function setPricingURLs(string[] calldata _pricingURLs) external onlyOwner {
    pricingURLs = _pricingURLs;
    IMasterAgreement(masterAgreement).updatePricingWssURLs(_pricingURLs);
  }

  function setMarketsURLs(string[] calldata _marketsURLs) external onlyOwner {
    marketsURLs = _marketsURLs;
    IMasterAgreement(masterAgreement).updateMarketsHttpsURLs(_marketsURLs);
  }

  function deposit(uint256 _amount) external onlyOwner {
    IMasterAgreement(masterAgreement).deposit(_amount);
  }

  function withdraw(uint256 _amount) external onlyOwner {
    IMasterAgreement(masterAgreement).withdraw(_amount);
  }

  function allocate(uint256 _amount) external onlyOwner {
    IMasterAgreement(masterAgreement).allocate(_amount);
  }

  function deallocate(uint256 _amount) external onlyOwner {
    IMasterAgreement(masterAgreement).deallocate(_amount);
  }

  function depositAndAllocate(uint256 _amount) external onlyOwner {
    IMasterAgreement(masterAgreement).depositAndAllocate(_amount);
  }

  function deallocateAndWithdraw(uint256 _amount) external onlyOwner {
    IMasterAgreement(masterAgreement).deallocateAndWithdraw(_amount);
  }

  function withdrawETH() external onlyOwner {
    uint256 balance = address(this).balance;
    (bool success, ) = payable(owner()).call{value: balance}("");
    require(success, "Failed to send Ether");
  }

  function callMasterAgreement(bytes calldata _data) external onlyOwner {
    _callMasterAgreement(_data);
  }

  function callMasterAgreementTrustee(bytes calldata _data) external onlyTrustedForwarder {
    _transferRelayFee();
    _callMasterAgreement(_data);
  }

  function _approveMasterAgreement() private {
    IERC20(collateral).safeApprove(masterAgreement, type(uint256).max);
  }

  function _enlist() private {
    IMasterAgreement(masterAgreement).enlist(pricingURLs, marketsURLs);
  }

  function _callMasterAgreement(bytes calldata _data) private {
    (bool success, ) = masterAgreement.call(_data);
    require(success, "MasterAgreement call failed");
  }
}

