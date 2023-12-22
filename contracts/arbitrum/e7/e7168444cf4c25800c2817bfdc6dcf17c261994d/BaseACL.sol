// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import "./EnumerableSet.sol";

import "./BaseAuthorizer.sol";

/// @title BaseACL - Basic ACL template which uses the call-self trick to perform function and parameters check.
/// @author Cobo Safe Dev Team https://www.cobo.com/
/// @dev Steps to extend this:
///        1. Set the NAME and VERSION.
///        2. Write ACL functions according the target contract.
///        3. Add a constructor. eg:
///           `constructor(address _owner, address _caller) BaseACL(_owner, _caller) {}`
///        4. Override `contracts()` to only target contracts that you checks. For txn
////          whose to address is not in the list `_preExecCheck()` will revert.
///        5. (Optional) If state changing operation in the checking method is required,
///           override `_preExecCheck()` to change `staticcall` to `call`.
///        6. (Optional) Override `permissions()` to summary your checking methods.
///
///      NOTE for ACL developers:
///        1. Implement your checking functions which should be defined extractly the same as
///           the target method to control so you do not bother to write a lot abi.decode code.
///        2. Checking funtions should NOT return any value, use `require` to perform your check.
///        3. BaseACL may serve for multiple target contracts.
///            - Implement contracts() to manage the target contracts set.
///            - Use `onlyContract` modifier or check `_txn.to` in checking functions.
///        4. Do NOT implement your own `setXXX` function, wrap your data into `Variant` and
///           use `setVariant` `getVariant` instead.
///        5. If you still need your own setter, ensure `onlyOwner` is used.

abstract contract BaseACL is BaseAuthorizer {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @dev Set such constants in sub contract.
    // bytes32 public constant NAME = "BaseACL";
    // uint256 public constant VERSION = 0;

    /// Only preExecCheck is used in ACL.
    uint256 public constant flag = AuthFlags.HAS_PRE_CHECK_MASK;

    EnumerableSet.Bytes32Set names;
    mapping(bytes32 => Variant) public variants; // name => Variant

    /// @dev Temporary storage variable to pass transaction to check functions.
    TransactionData internal _txn;

    event VariantSet(bytes32 indexed name);

    constructor(address _owner, address _caller) BaseAuthorizer(_owner, _caller) {}

    /// Internal functions.
    function _parseReturnData(
        bool success,
        bytes memory revertData
    ) internal pure returns (AuthorizerReturnData memory authData) {
        if (success) {
            // ACL check function should return empty bytes which differs from normal view functions.
            require(revertData.length == 0, Errors.ACL_FUNC_RETURNS_NON_EMPTY);
            authData.result = AuthResult.SUCCESS;
        } else {
            if (revertData.length < 68) {
                // 4(Error sig) + 32(offset) + 32(length)
                authData.message = string(revertData);
            } else {
                assembly {
                    // Slice the sighash.
                    revertData := add(revertData, 0x04)
                }
                authData.message = abi.decode(revertData, (string));
            }
        }
    }

    function _commonCheck(TransactionData calldata transaction) internal virtual {
        // This works as a catch-all check. Sample but safer.
        address to = transaction.to;
        address[] memory _contracts = contracts(); // Call external.
        for (uint i = 0; i < _contracts.length; i++) {
            if (to == _contracts[i]) return;
        }
        revert(Errors.NOT_IN_CONTRACT_LIST);
    }

    function _preExecCheck(
        TransactionData calldata transaction
    ) internal virtual override returns (AuthorizerReturnData memory authData) {
        _commonCheck(transaction);

        _txn = transaction;

        (bool success, bytes memory revertData) = address(this).staticcall(transaction.data);

        // gas refund.
        _txn.from = address(1);
        _txn.delegate = address(1);
        _txn.to = address(1);
        _txn.value = 1;
        _txn.data = hex"ff";

        return _parseReturnData(success, revertData);
    }

    function _postExecCheck(
        TransactionData calldata transaction,
        TransactionResult calldata callResult,
        AuthorizerReturnData calldata preData
    ) internal virtual override returns (AuthorizerReturnData memory authData) {
        authData.result = AuthResult.SUCCESS;
    }

    // Internal view functions.
    // Should only used in _preExecCheck/_postExecCheck
    function checkRecipient(address _recipient) internal view {
        require(_recipient == _txn.from, "Invalid recipient");
    }

    function checkContract(address _contract) internal view {
        require(_contract == _txn.to, "Invalid contract");
    }

    // Modifiers.

    modifier onlyContract(address _contract) {
        checkContract(_contract);
        _;
    }

    /// External functions

    function setVariant(bytes32 name, Variant calldata v) external virtual onlyOwner {
        require(v.varType == VariantType.RAW, Errors.INVALID_VAR_TYPE);
        variants[name] = v;
        names.add(name);
        emit VariantSet(name);
    }

    /// External view functions

    function getVariant(bytes32 name) public view virtual returns (Variant memory v) {
        v = variants[name];
        require(v.varType == VariantType.RAW, Errors.INVALID_VAR_TYPE);
    }

    function getAllVariants() external view virtual returns (bytes32[] memory _names, Variant[] memory _vars) {
        uint256 size = names.length();
        _names = new bytes32[](size);
        _vars = new Variant[](size);
        for (uint i = 0; i < size; ++i) {
            bytes32 name = names.at(i);
            _names[i] = name;
            _vars[i] = variants[name];
        }
    }

    /// @dev Implement your own access control checking functions here.

    // example:

    // function transfer(address to, uint256 amount)
    //     onlyContract(USDT_ADDR)
    //     external view
    // {
    //     require(amount > 0 & amount < 10000, "amount not in range");
    // }

    /// @dev Override this as `_preExecCheck` used.
    function contracts() public view virtual returns (address[] memory _contracts) {}

    fallback() external virtual {
        revert(Errors.METHOD_NOT_ALLOW);
    }
}

