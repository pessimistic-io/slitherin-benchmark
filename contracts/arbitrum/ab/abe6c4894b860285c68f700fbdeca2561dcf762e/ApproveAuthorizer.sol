// commit b6c3fbfce7de808c18de3897cd6e6243710e18b6
// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import "./EnumerableSet.sol";

import "./BaseACL.sol";

/// @title ApproveAuthorizer - Manages ERC20/ETH approve permissons.
/// @author Cobo Safe Dev Team https://www.cobo.com/
/// @notice This checks token-spender pairs, no value is restricted.
contract ApproveAuthorizer is BaseAuthorizer {
    bytes32 public constant NAME = "ApproveAuthorizer";
    uint256 public constant VERSION = 1;
    bytes32 public constant override TYPE = AuthType.APPROVE;
    uint256 public constant flag = AuthFlags.HAS_PRE_CHECK_MASK;

    // function approve(address spender, uint256 value)
    bytes4 constant APPROVE_SELECTOR = 0x095ea7b3;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet tokenSet;

    mapping(address => EnumerableSet.AddressSet) tokenToSpenders;

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

    event TokenSpenderAdded(address indexed token, address indexed spender);
    event TokenSpenderRemoved(address indexed token, address indexed spender);

    struct TokenSpender {
        address token;
        address spender;
    }

    constructor(address _owner, address _caller) BaseAuthorizer(_owner, _caller) {}

    /// @notice Add token-receiver pairs.
    function addTokenSpenders(TokenSpender[] calldata tokenSpenders) external onlyOwner {
        for (uint i = 0; i < tokenSpenders.length; i++) {
            address token = tokenSpenders[i].token;
            address spender = tokenSpenders[i].spender;
            if (tokenSet.add(token)) {
                emit TokenAdded(token);
            }

            if (tokenToSpenders[token].add(spender)) {
                emit TokenSpenderAdded(token, spender);
            }
        }
    }

    function removeTokenSpenders(TokenSpender[] calldata tokenSpenders) external onlyOwner {
        for (uint i = 0; i < tokenSpenders.length; i++) {
            address token = tokenSpenders[i].token;
            address spender = tokenSpenders[i].spender;
            if (tokenToSpenders[token].remove(spender)) {
                emit TokenSpenderRemoved(token, spender);
                if (tokenToSpenders[token].length() == 0) {
                    if (tokenSet.remove(token)) {
                        emit TokenRemoved(token);
                    }
                }
            }
        }
    }

    // View functions.

    function getAllToken() external view returns (address[] memory) {
        return tokenSet.values();
    }

    /// @dev View function allow user to specify the range in case we have very big token set
    ///      which can exhaust the gas of block limit.
    function getTokens(uint256 start, uint256 end) external view returns (address[] memory) {
        uint256 size = tokenSet.length();
        if (end > size) end = size;
        require(start < end, "start >= end");
        address[] memory _tokens = new address[](end - start);
        for (uint i = 0; i < end - start; i++) {
            _tokens[i] = tokenSet.at(start + i);
        }
        return _tokens;
    }

    function getTokenSpenders(address token) external view returns (address[] memory) {
        return tokenToSpenders[token].values();
    }

    function _preExecCheck(
        TransactionData calldata transaction
    ) internal virtual override returns (AuthorizerReturnData memory authData) {
        if (
            transaction.data.length >= 68 && // 4 + 32 + 32
            bytes4(transaction.data[0:4]) == APPROVE_SELECTOR &&
            transaction.value == 0
        ) {
            (address spender /*uint256 value*/, ) = abi.decode(transaction.data[4:], (address, uint256));
            address token = transaction.to;
            if (tokenToSpenders[token].contains(spender)) {
                authData.result = AuthResult.SUCCESS;
                return authData;
            }
        }
        authData.result = AuthResult.FAILED;
        authData.message = "approve not allowed";
    }

    function _postExecCheck(
        TransactionData calldata transaction,
        TransactionResult calldata callResult,
        AuthorizerReturnData calldata preData
    ) internal virtual override returns (AuthorizerReturnData memory authData) {
        authData.result = AuthResult.SUCCESS;
    }
}

