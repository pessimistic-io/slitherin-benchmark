// commit 4a1e464ba0e7d0bc60b79fcbe742d43c6c344f2a
// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import "./Types.sol";

interface IAuthorizer {
    function flag() external view returns (uint256 authFlags);

    function setCaller(address _caller) external;

    function preExecCheck(TransactionData calldata transaction) external returns (AuthorizerReturnData memory authData);

    function postExecCheck(
        TransactionData calldata transaction,
        TransactionResult calldata callResult,
        AuthorizerReturnData calldata preAuthData
    ) external returns (AuthorizerReturnData memory authData);

    function preExecProcess(TransactionData calldata transaction) external;

    function postExecProcess(TransactionData calldata transaction, TransactionResult calldata callResult) external;
}

interface IAuthorizerSupportingHint is IAuthorizer {
    // When IAuthorizer(auth).flag().supportHint() == true;
    function collectHint(
        AuthorizerReturnData calldata preAuthData,
        AuthorizerReturnData calldata postAuthData
    ) external view returns (bytes memory hint);
}

