// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16;

import {ERC2771Context} from "./ERC2771Context.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";

contract HedgerRelayer is ERC2771Context {
  using SafeERC20 for IERC20;

  address private _owner;
  address public masterAgreement;
  address public collateral;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}

  constructor(
    address trustedForwarder,
    address _masterAgreement,
    address _collateral
  ) ERC2771Context(trustedForwarder) {
    _transferOwnership(_msgSender());
    masterAgreement = _masterAgreement;
    collateral = _collateral;
  }

  /**
   * @dev Throws if called by any account other than the Trusted Forwarder.
   */
  modifier onlyTrustedForwarder() {
    require(isTrustedForwarder(msg.sender), "Only callable by Trusted Forwarder");
    _;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    _checkOwner();
    _;
  }

  modifier onlyOwnerOrTrustedForwarder() {
    require(owner() == _msgSender() || isTrustedForwarder(msg.sender), "Only owner or Trusted Forwarder");
    _;
  }

  /**
   * @dev Returns the address of the current owner.
   */
  function owner() public view virtual returns (address) {
    return _owner;
  }

  /**
   * @dev Throws if the sender is not the owner.
   */
  function _checkOwner() internal view virtual {
    require(owner() == _msgSender(), "Ownable: caller is not the owner");
  }

  /**
   * @dev Transfers ownership of the contract to a new account (`newOwner`).
   * Can only be called by the current owner.
   */
  function transferOwnership(address newOwner) public virtual onlyOwner {
    require(newOwner != address(0), "Ownable: new owner is the zero address");
    _transferOwnership(newOwner);
  }

  /**
   * @dev Transfers ownership of the contract to a new account (`newOwner`).
   * Internal function without access restriction.
   */
  function _transferOwnership(address newOwner) internal virtual {
    address oldOwner = _owner;
    _owner = newOwner;
    emit OwnershipTransferred(oldOwner, newOwner);
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

  function callMasterAgreement(bytes calldata _data) external onlyOwnerOrTrustedForwarder {
    (bool success, ) = masterAgreement.call(_data);
    require(success, "MasterAgreement call failed");
  }

  function withdrawETH() external onlyOwner {
    uint256 balance = address(this).balance;
    (bool success, ) = payable(owner()).call{value: balance}("");
    require(success, "Failed to send Ether");
  }
}

