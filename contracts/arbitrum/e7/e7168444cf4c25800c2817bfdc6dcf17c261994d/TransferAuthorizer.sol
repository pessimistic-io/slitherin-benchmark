// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import "./EnumerableSet.sol";

import "./BaseACL.sol";

/// @title TransferAuthorizer - Manages ERC20/ETH transfer permissons.
/// @author Cobo Safe Dev Team https://www.cobo.com/
/// @notice This checks token-receiver pairs, no amount is restricted.
contract TransferAuthorizer is BaseACL {
    bytes32 public constant NAME = "TransferAuthorizer";
    uint256 public constant VERSION = 1;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet tokenSet;

    mapping(address => EnumerableSet.AddressSet) tokenToReceivers;

    event TokenReceiverAdded(address indexed token, address indexed receiver);
    event TokenReceiverRemoved(address indexed token, address indexed receiver);

    struct TokenReceiver {
        address token;
        address receiver;
    }

    constructor(address _owner, address _caller) BaseACL(_owner, _caller) {}

    function _commonCheck(TransactionData calldata transaction) internal override {
        // Remove common target address check.
        // This should be done in `transfer()`.
    }

    function _checkTransfer(address token, address receiver) internal view {
        require(tokenToReceivers[token].contains(receiver), "Transfer not allowed");
    }

    // External functions.

    /// @notice Add token-receiver pairs. Use 0xee..ee for native ETH.
    function addTokenReceivers(TokenReceiver[] calldata tokenReceivers) external onlyOwner {
        for (uint i = 0; i < tokenReceivers.length; i++) {
            tokenSet.add(tokenReceivers[i].token);
            tokenToReceivers[tokenReceivers[i].token].add(tokenReceivers[i].receiver);

            emit TokenReceiverAdded(tokenReceivers[i].token, tokenReceivers[i].receiver);
        }
    }

    function removeTokenReceivers(TokenReceiver[] calldata tokenReceivers) external onlyOwner {
        for (uint i = 0; i < tokenReceivers.length; i++) {
            tokenToReceivers[tokenReceivers[i].token].remove(tokenReceivers[i].receiver);

            emit TokenReceiverRemoved(tokenReceivers[i].token, tokenReceivers[i].receiver);
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

    function getTokenReceivers(address token) external view returns (address[] memory) {
        return tokenToReceivers[token].values();
    }

    // ACL check functions.
    function transfer(address recipient, uint256 amount) external view {
        require(_txn.value == 0, "ETH transfer not allowed in ERC20 transfer");
        _checkTransfer(_txn.to, recipient);
    }

    fallback() external override {
        require(_txn.data.length == 0, "Only transfer() allowed in TransferAuthorizer");
        require(_txn.value > 0, "Value = 0");
        _checkTransfer(ETH, _txn.to);
    }
}

