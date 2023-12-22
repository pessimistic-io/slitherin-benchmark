// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import {ISignatureTransfer} from "./ISignatureTransfer.sol";
import {BasicInfo} from "./SocketStructs.sol";

// Library to get Permit 2 related data.
library Permit2Lib {
    string public constant TOKEN_PERMISSIONS_TYPE =
        "TokenPermissions(address token,uint256 amount)";

    function toPermit(
        BasicInfo memory info
    ) internal pure returns (ISignatureTransfer.PermitTransferFrom memory) {
        return
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: info.inputToken,
                    amount: info.inputAmount
                }),
                nonce: info.nonce,
                deadline: info.deadline
            });
    }

    function transferDetails(
        BasicInfo memory info,
        address spender
    )
        internal
        pure
        returns (ISignatureTransfer.SignatureTransferDetails memory)
    {
        return
            ISignatureTransfer.SignatureTransferDetails({
                to: spender,
                requestedAmount: info.inputAmount
            });
    }
}

