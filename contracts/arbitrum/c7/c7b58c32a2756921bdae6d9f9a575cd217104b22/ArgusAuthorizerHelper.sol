// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import "./CoboSafeAccount.sol";
import "./FlatRoleManager.sol";
import "./ArgusRootAuthorizer.sol";
import "./FuncAuthorizer.sol";
import "./TransferAuthorizer.sol";
import "./DEXBaseACL.sol";

abstract contract ArgusAuthorizerHelper {
    function setFuncAuthorizerParams(
        address authorizerAddress,
        address[] calldata _contracts,
        string[][] calldata funcLists
    ) public {
        if (_contracts.length == 0) return;
        FuncAuthorizer authorizer = FuncAuthorizer(authorizerAddress);
        for (uint i = 0; i < _contracts.length; i++) {
            authorizer.addContractFuncs(_contracts[i], funcLists[i]);
        }
    }

    function unsetFuncAuthorizerParams(
        address authorizerAddress,
        address[] calldata _contracts,
        string[][] calldata funcLists
    ) external {
        if (_contracts.length == 0) return;
        FuncAuthorizer authorizer = FuncAuthorizer(authorizerAddress);
        for (uint i = 0; i < _contracts.length; i++) {
            authorizer.removeContractFuncs(_contracts[i], funcLists[i]);
        }
    }

    function setTransferAuthorizerParams(
        address authorizerAddress,
        TransferAuthorizer.TokenReceiver[] calldata tokenReceivers
    ) public {
        if (tokenReceivers.length == 0) return;
        TransferAuthorizer authorizer = TransferAuthorizer(authorizerAddress);
        authorizer.addTokenReceivers(tokenReceivers);
    }

    function unsetTransferAuthorizerParams(
        address authorizerAddress,
        TransferAuthorizer.TokenReceiver[] calldata tokenReceivers
    ) external {
        if (tokenReceivers.length == 0) return;
        TransferAuthorizer authorizer = TransferAuthorizer(authorizerAddress);
        authorizer.removeTokenReceivers(tokenReceivers);
    }

    function setDexAuthorizerParams(
        address authorizerAddress,
        address[] calldata _swapInTokens,
        address[] calldata _swapOutTokens
    ) public {
        changeDexAuthorizerParams(authorizerAddress, _swapInTokens, _swapOutTokens, true);
    }

    function unsetDexAuthorizerParams(
        address authorizerAddress,
        address[] calldata _swapInTokens,
        address[] calldata _swapOutTokens
    ) external {
        changeDexAuthorizerParams(authorizerAddress, _swapInTokens, _swapOutTokens, false);
    }

    function changeDexAuthorizerParams(
        address authorizerAddress,
        address[] calldata _swapInTokens,
        address[] calldata _swapOutTokens,
        bool tokenStatus
    ) internal {
        if (_swapInTokens.length == 0 && _swapOutTokens.length == 0) return;
        DEXBaseACL authorizer = DEXBaseACL(authorizerAddress);
        if (_swapInTokens.length > 0) {
            // populate SwapInToken
            DEXBaseACL.SwapInToken[] memory swapInTokens = new DEXBaseACL.SwapInToken[](_swapInTokens.length);
            for (uint i = 0; i < _swapInTokens.length; i++) {
                swapInTokens[i] = DEXBaseACL.SwapInToken(_swapInTokens[i], tokenStatus);
            }

            authorizer.setSwapInTokens(swapInTokens);
        }
        if (_swapOutTokens.length > 0) {
            // populate SwapOutToken
            DEXBaseACL.SwapOutToken[] memory swapOutTokens = new DEXBaseACL.SwapOutToken[](_swapOutTokens.length);
            for (uint i = 0; i < _swapOutTokens.length; i++) {
                swapOutTokens[i] = DEXBaseACL.SwapOutToken(_swapOutTokens[i], tokenStatus);
            }
            authorizer.setSwapOutTokens(swapOutTokens);
        }
    }
}

