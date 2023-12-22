// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ConnextXERC20} from "./ConnextXERC20.sol";
import {XERC20Lockbox} from "./XERC20Lockbox.sol";
import {IXERC20Factory} from "./IXERC20Factory.sol";
import {TransparentUpgradeableProxy} from "./TransparentUpgradeableProxy.sol";
import {CREATE3} from "./CREATE3.sol";
import {CREATE3Factory} from "./CREATE3Factory.sol";
import {EnumerableSet} from "./EnumerableSet.sol";

contract XERC20Factory is IXERC20Factory {
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(bytes32 => address) public deployed;

  /**
   * @notice Address of the xerc20 maps to the address of its lockbox if it has one
   */
  mapping(address => address) public lockboxRegistry;

  /**
   * @notice The set of registered ConnextXERC20 tokens
   */
  EnumerableSet.AddressSet internal _xerc20RegistryArray;

  CREATE3Factory public immutable factory = CREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

  /**
   * @notice Deploys an ConnextXERC20 contract using CREATE3
   * @dev _limits and _minters must be the same length
   * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _bridges The array of bridges that you are adding (optional, can be an empty array)
   */
  function deployXERC20(
    address _owner,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges
  ) external returns (address _xerc20) {
    _xerc20 = _deployUpgradeableXERC20("Connext Token", "NEXT", _owner, _minterLimits, _burnerLimits, _bridges);

    emit XERC20Deployed(_xerc20);
  }

  /**
   * @notice Deploys an XERC20Lockbox contract using CREATE3
   *
   * @param _xerc20 The address of the xerc20 that you want to deploy a lockbox for
   * @param _baseToken The address of the base token that you want to lock
   * @param _isNative Whether or not the base token is native
   */

  function deployLockbox(
    address _owner,
    address _xerc20,
    address _baseToken,
    bool _isNative
  ) external returns (address payable _lockbox) {
    if (_baseToken == address(0) && !_isNative) revert IXERC20Factory_BadTokenAddress();

    if (ConnextXERC20(_xerc20).owner() != msg.sender) revert IXERC20Factory_NotOwner();
    if (lockboxRegistry[_xerc20] != address(0)) revert IXERC20Factory_LockboxAlreadyDeployed();

    _lockbox = _deployUpgradeableLockbox(_owner, _xerc20, _baseToken, _isNative);

    emit LockboxDeployed(_lockbox);
  }

  /**
   * @notice Returns if an ConnextXERC20 is registered
   *
   * @param _xerc20 The address of the ConnextXERC20
   * @return _result If the ConnextXERC20 is registered
   */

  function isRegisteredXERC20(address _xerc20) external view returns (bool _result) {
    _result = EnumerableSet.contains(_xerc20RegistryArray, _xerc20);
  }

  /**
   * @notice Deploys an ConnextXERC20 contract using CREATE3
   * @dev _limits and _minters must be the same length
   * @param _name The name of the token
   * @param _symbol The symbol of the token
   * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _bridges The array of burners that you are adding (optional, can be an empty array)
   */
  function _deployUpgradeableXERC20(
    string memory _name,
    string memory _symbol,
    address _owner,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges
  ) internal returns (address _xerc20) {
    uint256 _bridgesLength = _bridges.length;
    if (_minterLimits.length != _bridgesLength || _burnerLimits.length != _bridgesLength) {
      revert IXERC20Factory_InvalidLength();
    }
    bytes32 _salt = keccak256(abi.encodePacked(_name, _symbol, msg.sender));
    bytes32 _implementationSalt = keccak256(abi.encodePacked(_salt, "implementation"));

    // deploy implementation
    address _implementation = CREATE3.deploy(_implementationSalt, type(ConnextXERC20).creationCode, 0);
    emit XERC20ImplementationDeployed(_implementation);

    // deploy proxy with create3
    bytes memory _creation = type(TransparentUpgradeableProxy).creationCode;
    bytes memory _initData = abi.encodeWithSelector(ConnextXERC20.initialize.selector, _owner, _owner, _bridges, _minterLimits, _burnerLimits);
    bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_implementation, _owner, _initData));

    // set xerc20 to proxy address
    _xerc20 = CREATE3.deploy(_salt, _bytecode, 0);

    EnumerableSet.add(_xerc20RegistryArray, _xerc20);
  }

  function _deployUpgradeableLockbox(
    address _owner,
    address _xerc20,
    address _baseToken,
    bool _isNative
  ) internal returns (address payable _lockbox) {
    bytes32 _salt = keccak256(abi.encodePacked(_xerc20, _baseToken, msg.sender));
    bytes32 _implementationSalt = keccak256(abi.encodePacked(_salt, "implementation"));

    // deploy lockbox
    bytes memory _creation = type(XERC20Lockbox).creationCode;
    address _implementation = payable(CREATE3.deploy(_implementationSalt, _creation, 0));
    emit LockboxImplementationDeployed(_implementation);

    // deploy proxy with create3
    _creation = type(TransparentUpgradeableProxy).creationCode;
    bytes memory _initData = abi.encodeWithSelector(XERC20Lockbox.initialize.selector, _xerc20, _baseToken, _isNative);
    bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_implementation, _owner, _initData));

    // set lockbox to proxy address
    _lockbox = payable(CREATE3.deploy(_salt, _bytecode, 0));
  }
}
