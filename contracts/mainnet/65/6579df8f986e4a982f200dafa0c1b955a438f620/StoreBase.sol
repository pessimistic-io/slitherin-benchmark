// Neptune Mutual Protocol (https://neptunemutual.com)
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "./IStore.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

abstract contract StoreBase is IStore, Pausable, Ownable {
  using SafeERC20 for IERC20;

  mapping(bytes32 => int256) public intStorage;
  mapping(bytes32 => uint256) public uintStorage;
  mapping(bytes32 => uint256[]) public uintsStorage;
  mapping(bytes32 => address) public addressStorage;
  mapping(bytes32 => mapping(address => bool)) public addressBooleanStorage;
  mapping(bytes32 => string) public stringStorage;
  mapping(bytes32 => bytes) public bytesStorage;
  mapping(bytes32 => bytes32) public bytes32Storage;
  mapping(bytes32 => bool) public boolStorage;
  mapping(bytes32 => address[]) public addressArrayStorage;
  mapping(bytes32 => mapping(address => uint256)) public addressArrayPositionMap;
  mapping(bytes32 => bytes32[]) public bytes32ArrayStorage;
  mapping(bytes32 => mapping(bytes32 => uint256)) public bytes32ArrayPositionMap;

  mapping(address => bool) public pausers;

  bytes32 private constant _NS_MEMBERS = "ns:members";

  constructor() {
    boolStorage[keccak256(abi.encodePacked(_NS_MEMBERS, msg.sender))] = true;
    boolStorage[keccak256(abi.encodePacked(_NS_MEMBERS, address(this)))] = true;
  }

  /**
   *
   * @dev Accepts a list of accounts and their respective statuses for addition or removal as pausers.
   *
   * @custom:suppress-reentrancy Risk tolerable. Can only be called by the owner.
   * @custom:suppress-address-trust-issue Risk tolerable.
   */
  function setPausers(address[] calldata accounts, bool[] calldata statuses) external override onlyOwner whenNotPaused {
    require(accounts.length > 0, "No pauser specified");
    require(accounts.length == statuses.length, "Invalid args");

    for (uint256 i = 0; i < accounts.length; i++) {
      pausers[accounts[i]] = statuses[i];
    }

    emit PausersSet(msg.sender, accounts, statuses);
  }

  /**
   * @dev Recover all Ether held by the contract.
   * @custom:suppress-reentrancy Risk tolerable. Can only be called by the owner.
   * @custom:suppress-pausable Risk tolerable. Can only be called by the owner.
   */
  function recoverEther(address sendTo) external onlyOwner {
    // slither-disable-next-line low-level-calls
    (bool success, ) = payable(sendTo).call{value: address(this).balance}(""); // solhint-disable-line avoid-low-level-calls
    require(success, "Recipient may have reverted");
  }

  /**
   * @dev Recover all IERC-20 compatible tokens sent to this address.
   *
   * @custom:suppress-reentrancy Risk tolerable. Can only be called by the owner.
   * @custom:suppress-pausable Risk tolerable. Can only be called by the owner.
   * @custom:suppress-malicious-erc Risk tolerable. Although the token can't be trusted, the owner has to check the token code manually.
   * @custom:suppress-address-trust-issue Risk tolerable. Although the token can't be trusted, the owner has to check the token code manually.
   *
   * @param token IERC-20 The address of the token contract
   */
  function recoverToken(address token, address sendTo) external onlyOwner {
    IERC20 erc20 = IERC20(token);

    uint256 balance = erc20.balanceOf(address(this));

    if (balance > 0) {
      // slither-disable-next-line unchecked-transfer
      erc20.safeTransfer(sendTo, balance);
    }
  }

  /**
   * @dev Pauses the store
   *
   * @custom:suppress-reentrancy Risk tolerable. Can only be called by a pauser.
   *
   */
  function pause() external {
    require(pausers[msg.sender], "Forbidden");
    super._pause();
  }

  /**
   * @dev Unpauses the store
   *
   * @custom:suppress-reentrancy Risk tolerable. Can only be called by the owner.
   *
   */
  function unpause() external onlyOwner {
    super._unpause();
  }

  function isProtocolMemberInternal(address contractAddress) public view returns (bool) {
    return boolStorage[keccak256(abi.encodePacked(_NS_MEMBERS, contractAddress))];
  }

  function _throwIfPaused() internal view {
    require(super.paused() == false, "Pausable: paused");
  }

  function _throwIfSenderNotProtocolMember() internal view {
    require(isProtocolMemberInternal(msg.sender), "Forbidden");
  }
}

