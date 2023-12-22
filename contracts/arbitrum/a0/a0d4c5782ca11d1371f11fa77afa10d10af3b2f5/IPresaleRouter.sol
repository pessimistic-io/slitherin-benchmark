// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.0;

import "./ISwapRouter.sol";

import "./IPresale.sol";

interface IPresaleRouter {
    // the remote chainId sending the tokens
    // the remote Bridge address
    // the token contract on the local chain
    // the qty of local _token contract tokens
    event ReceiveStargate(
        uint16 srcChainId, bytes srcAddress, uint256 nonce, address token, uint256 amountLD, bytes payload
    );

    event PurchaseResult(PurchaseParams params, bool success, IPresale.Receipt receipt, address indexed sender);

    struct PurchaseParams {
        address account;
        uint256 assetAmount;
        address referrer;
    }

    function purchase(PurchaseParams memory params) external;
}

