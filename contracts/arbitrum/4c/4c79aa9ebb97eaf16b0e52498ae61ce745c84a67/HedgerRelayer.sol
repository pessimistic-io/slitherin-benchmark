// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16;

import {ERC2771Context} from "./ERC2771Context.sol";
import {GelatoRelayContext} from "./GelatoRelayContext.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";

contract HedgerRelayer is ERC2771Context, GelatoRelayContext {
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
    _approveMasterAgreement();
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
    _approveMasterAgreement();
  }

  function setCollateral(address _collateral) external onlyOwner {
    collateral = _collateral;
    _approveMasterAgreement();
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

  function _callMasterAgreement(bytes calldata _data) private {
    (bool success, bytes memory returnData) = masterAgreement.call(_data);
    require(success, _getRevertMsg(returnData));
  }

  function withdrawETH() external onlyOwner {
    uint256 balance = address(this).balance;
    (bool success, ) = payable(owner()).call{value: balance}("");
    require(success, "Failed to send Ether");
  }

  function _getRevertMsg(bytes memory _returnData) private pure returns (string memory) {
    // If the _res length is less than 68, then the transaction failed silently (without a revert message)
    if (_returnData.length < 68) return "Transaction reverted silently";

    assembly {
      // Slice the sighash.
      _returnData := add(_returnData, 0x04)
    }
    return abi.decode(_returnData, (string)); // All that remains is the revert string
  }
}

