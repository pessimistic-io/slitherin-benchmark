// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./GnosisSafe.sol";
import "./Enums.sol";
import "./Permissions.sol";

contract SafeModule is Ownable {
  string public constant version = "0.2.0";
  uint256 internal constant _MAX_ROLE_PER_MEMBER = 16;

  event ModuleSetup(address owner, address safeProxy);
  event AssignRoles(address member, bytes32[_MAX_ROLE_PER_MEMBER] roleNames);
  event DeprecateRole(bytes32 roleName);

  event ExecTransaction(
    address to,
    uint256 value,
    bytes data,
    Operation operation,
    address sender
  );

  mapping(bytes32 => Role) internal roles;
  mapping(address => bytes32[_MAX_ROLE_PER_MEMBER]) internal members;
  mapping(bytes32 => bool) internal deprecatedRoles;

  address public _safeProxy;

  constructor(address owner, address payable safeProxy) {
    bytes memory initParams = abi.encode(owner, safeProxy);
    setUp(initParams);
  }

  function setUp(bytes memory initParams) public {
    (address owner, address safeProxy) = abi.decode(
      initParams,
      (address, address)
    );

    require(safeProxy != address(0), "Invalid safe proxy");
    require(owner != address(0), "Invalid owner");

    _setupOwner(owner);
    _safeProxy = safeProxy;

    emit ModuleSetup(owner, safeProxy);
  }

  modifier isValidRoleName(bytes32 roleName) {
    require(roleName != 0, "SafeModule: empty role name");
    require(!deprecatedRoles[roleName], "SafeModule: role deprecated");

    _;
  }

  /// @dev Assign roles to a member
  /// @param member address
  /// @param roleNames Id of a roles
  /// @notice Can only be called by owner
  function assignRoles(address member, bytes32[] memory roleNames)
    external
    onlyOwner
  {
    for (uint256 i = 0; i < _MAX_ROLE_PER_MEMBER; ++i) {
      bytes32 roleName = i < roleNames.length ? roleNames[i] : bytes32(0);
      require(!deprecatedRoles[roleName], "SafeModule: role deprecated");

      members[member][i] = roleName;
    }

    emit AssignRoles(member, members[member]);
  }

  /// @dev Deprecate a roleName and this roleName can't used anymore
  /// @param roleName Id of a role
  /// @notice Can only be called by owner
  function deprecateRole(bytes32 roleName)
    external
    onlyOwner
    isValidRoleName(roleName)
  {
    deprecatedRoles[roleName] = true;
    emit DeprecateRole(roleName);
  }

  /// @dev Get roles of an address for now
  /// @param member Member address
  function rolesOf(address member)
    public
    view
    returns (bytes32[] memory validRoles)
  {
    validRoles = new bytes32[](_MAX_ROLE_PER_MEMBER);

    for (uint256 i = 0; i < _MAX_ROLE_PER_MEMBER; ++i) {
      bytes32 roleName = members[member][i];

      if (roleName == 0 || deprecatedRoles[roleName]) {
        continue;
      }

      validRoles[i] = roleName;
    }
  }

  function hasRole(address member, bytes32 roleName)
    public
    view
    returns (bool)
  {
    bytes32[] memory validRoles = rolesOf(member);

    for (uint256 i = 0; i < validRoles.length; ++i) {
      if (validRoles[i] == roleName) {
        return true;
      }
    }

    return false;
  }

  /// @dev Allow the specific roleName to call the contract
  /// @param roleName Id of a role
  /// @param theContract Allowed contract
  /// @param operation Defines the operation is call or delegateCall
  /// @notice Can only be called by owner
  function allowContract(
    bytes32 roleName,
    address theContract,
    Operation operation
  ) external onlyOwner isValidRoleName(roleName) {
    Permissions.allowContract(
      roles[roleName],
      roleName,
      theContract,
      operation
    );
  }

  /// @dev Disable the specific roleName to call the contract
  /// @param roleName Id of a role
  /// @param theContract Allowed contract
  /// @notice Can only be called by owner
  function revokeContract(bytes32 roleName, address theContract)
    external
    onlyOwner
    isValidRoleName(roleName)
  {
    Permissions.revokeContract(roles[roleName], roleName, theContract);
  }

  /// @dev Allow the specific roleName to call the function of contract
  /// @param roleName Id of a role
  /// @param theContract Allowed contract
  /// @notice Can only be called by owner
  function scopeContract(bytes32 roleName, address theContract)
    external
    onlyOwner
    isValidRoleName(roleName)
  {
    Permissions.scopeContract(roles[roleName], roleName, theContract);
  }

  /// @dev Allow the specific roleName to call the function
  /// @param roleName Id of a role
  /// @param theContract Allowed contract
  /// @param funcSig Function selector
  /// @param operation Defines the operation is call or delegateCall
  /// @notice Can only be called by owner
  /// @notice Please call 'scopeContract' at the begin before config function
  function allowFunction(
    bytes32 roleName,
    address theContract,
    bytes4 funcSig,
    Operation operation
  ) external onlyOwner isValidRoleName(roleName) {
    Permissions.allowFunction(
      roles[roleName],
      roleName,
      theContract,
      funcSig,
      operation
    );
  }

  /// @dev Disable the specific roleName to call the function
  /// @param roleName Id of a role
  /// @param theContract Allowed contract
  /// @param funcSig Function selector
  /// @notice Can only be called by owner
  function revokeFunction(
    bytes32 roleName,
    address theContract,
    bytes4 funcSig
  ) external onlyOwner isValidRoleName(roleName) {
    Permissions.revokeFunction(roles[roleName], roleName, theContract, funcSig);
  }

  /// @dev Allow the specific roleName to call the function with specific parameters
  /// @param roleName Id of a role
  /// @param theContract Allowed contract
  /// @param funcSig Function selector
  /// @param isScopeds List of parameter scoped config, false for un-scoped, true for scoped
  /// @param parameterTypes List of parameter types, Static, Dynamic or Dynamic32, use Static type if not scoped
  /// @param comparisons List of parameter comparison types, Eq, Gte or Lte, use Eq if not scoped
  /// @param targetValues List of expected values, use '0x' if not scoped
  /// @param operation Defines the operation is call or delegateCall
  /// @notice Can only be called by owner
  /// @notice Please call 'scopeContract' at the begin before config function
  function scopeFunction(
    bytes32 roleName,
    address theContract,
    bytes4 funcSig,
    uint256 ethValueLimit,
    bool[] memory isScopeds,
    ParameterType[] memory parameterTypes,
    Comparison[] memory comparisons,
    bytes[] calldata targetValues,
    Operation operation
  ) external onlyOwner isValidRoleName(roleName) {
    Permissions.scopeFunction(
      roles[roleName],
      roleName,
      theContract,
      funcSig,
      ethValueLimit,
      isScopeds,
      parameterTypes,
      comparisons,
      targetValues,
      operation
    );
  }

  /// @dev Check then exec transaction
  /// @param roleName role to execute this call
  /// @param to To address of the transaction
  /// @param value Ether value of the transaction
  /// @param data Data payload of the transaction
  /// @param operation Operation to execute the transaction, only call or delegateCall
  function execTransactionFromModule(
    bytes32 roleName,
    address to,
    uint256 value,
    bytes calldata data,
    Operation operation
  ) public {
    _execTransaction(roleName, to, value, data, operation);
  }

  struct Exec {
    bytes32 roleName;
    address to;
    uint256 value;
    bytes data;
    Operation operation;
  }

  function execTransactionsFromModule(Exec[] calldata execs) public {
    require(execs.length > 0, "SafeModule: Nothing to call");

    for (uint256 i = 0; i < execs.length; ++i) {
      Exec memory exec = execs[i];

      _execTransaction(
        exec.roleName,
        exec.to,
        exec.value,
        exec.data,
        exec.operation
      );
    }
  }

  function _execTransaction(
    bytes32 roleName,
    address to,
    uint256 value,
    bytes memory data,
    Operation operation
  ) internal isValidRoleName(roleName) {
    require(
      operation == Operation.Call || operation == Operation.DelegateCall,
      "SafeModule: only support call or delegatecall"
    );
    _verifyPermission(roleName, to, value, data, operation);

    require(
      GnosisSafe(payable(_safeProxy)).execTransactionFromModule(
        to,
        value,
        data,
        operation == Operation.DelegateCall
          ? GnosisSafeEnum.Operation.DelegateCall
          : GnosisSafeEnum.Operation.Call
      ),
      "SafeModule: execute fail on gnosis safe"
    );

    emit ExecTransaction(to, value, data, operation, _msgSender());
  }

  function _verifyPermission(
    bytes32 roleName,
    address to,
    uint256 value,
    bytes memory data,
    Operation operation
  ) internal view {
    require(
      hasRole(_msgSender(), roleName),
      "SafeModule: sender doesn't have this role"
    );

    Permissions.verify(roles[roleName], to, value, data, operation);
  }
}

