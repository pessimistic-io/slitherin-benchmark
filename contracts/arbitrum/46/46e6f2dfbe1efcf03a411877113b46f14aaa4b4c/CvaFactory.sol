// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./Ownable.sol";
import "./Pausable.sol";
import "./AccessControlEnumerable.sol";

import "./Clones.sol";
import "./ICvaFactory.sol";
import "./Cva.sol";

contract CvaFactory is AccessControlEnumerable, Ownable, Pausable, ICvaFactory {
  using Clones for address;

  bytes32 public constant WITHDRAWER_ROLE = keccak256('WITHDRAWER_ROLE');
  uint256 public validUntilBlock; // block.number

  bool public initialized;

  address public forwarderAddress; // chain VA
  address public bridgeAddress;
  address public handlerAddress;
  address public relayerAddress;
  address public wethAddress;
  address public deployerAddress;

  event ForwarderCreated(bytes userDID, address newForwarderAddress, uint256 createdAtTime, uint256 createAtBlock);

  event NativeReceived(address sender, address forwarderAddress, uint256 amount);

  function init(
    address _forwarderAddress,
    address _bridgeAddress,
    address _handlerAddress,
    address _relayerAddress,
    address _wethAddress,
    address _deployerAddress,
    address _ownerAddress
  ) external virtual {
    require(!initialized, 'bad');

    initialized = true;
    forwarderAddress = _forwarderAddress;
    bridgeAddress = _bridgeAddress;
    handlerAddress = _handlerAddress;
    relayerAddress = _relayerAddress;
    wethAddress = _wethAddress;
    deployerAddress = _deployerAddress;

    // set ownership
    _transferOwnership(_ownerAddress);

    _setupRole(DEFAULT_ADMIN_ROLE, _ownerAddress);
    _setupRole(WITHDRAWER_ROLE, _ownerAddress);
  }

  function owner() public view override(ICvaFactory, Ownable) returns (address) {
    return super.owner();
  }

  function hasRole(
    bytes32 role,
    address account
  ) public view override(AccessControl, IAccessControl, ICvaFactory) returns (bool) {
    return super.hasRole(role, account);
  }

  function getFinalSalt(bytes calldata _userDID, bytes calldata _salt) internal pure returns (bytes32 finalSalt) {
    finalSalt = keccak256(abi.encodePacked(_userDID, _salt));
  }

  function getForwarder(bytes calldata _userDID, bytes calldata _salt) external view returns (address) {
    return forwarderAddress.predictDeterministicAddress(getFinalSalt(_userDID, _salt));
  }

  function isForwarderDeployed(address _forwarderAddress) public view returns (bool) {
    return forwarderAddress.isClone(_forwarderAddress);
  }

  function createForwarder(bytes calldata _userDID, bytes calldata _salt) external whenNotPaused {
    require(_msgSender() == deployerAddress, '!deployer');
    require(isValid(), '!valid');

    address payable clone = payable(forwarderAddress.cloneDeterministic(getFinalSalt(_userDID, _salt)));

    // Initialize cva
    Cva(clone).init(_userDID, wethAddress);

    emit ForwarderCreated(_userDID, clone, block.timestamp, block.number);
  }

  function emitNativeReceived(address _sender, address _forwarderAddress, uint256 _amount) external {
    require(_msgSender() == _forwarderAddress && isForwarderDeployed(_forwarderAddress), '!forwarder');

    emit NativeReceived(_sender, _forwarderAddress, _amount);
  }

  function setForwarderAddress(address _forwarderAddress) external onlyOwner whenPaused {
    forwarderAddress = _forwarderAddress;
  }

  function setBridge(address _bridgeAddress) external onlyOwner whenPaused {
    bridgeAddress = _bridgeAddress;
  }

  function setHandler(address _handlerAddress) external onlyOwner whenPaused {
    handlerAddress = _handlerAddress;
  }

  function setRelayer(address _relayerAddress) external onlyOwner whenPaused {
    relayerAddress = _relayerAddress;
  }

  function setWETH(address _wethAddress) external onlyOwner whenPaused {
    wethAddress = _wethAddress;
  }

  function setDeployer(address _deployerAddress) external onlyOwner whenPaused {
    deployerAddress = _deployerAddress;
  }

  function setValidUntilBlock(uint256 _validUntilBlock) external onlyOwner whenPaused {
    validUntilBlock = _validUntilBlock;
  }

  function isValid() public view returns (bool) {
    if (validUntilBlock == 0) return true;

    return block.number <= validUntilBlock;
  }

  function togglePause() external onlyOwner {
    if (paused()) {
      _unpause();
    } else {
      _pause();
    }
  }

  function version() external pure returns (string memory) {
    return '1.0.0';
  }
}

