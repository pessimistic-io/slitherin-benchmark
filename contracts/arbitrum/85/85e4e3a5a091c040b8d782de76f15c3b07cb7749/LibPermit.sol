// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Permit} from "./ERC20Permit.sol";
import {IERC20} from "./IERC20.sol";
import {DataTypes} from "./DataTypes.sol";
import {IPermit2} from "./IPermit2.sol";

library LibPermit {
    function executePermit(address _asset, address _user, uint256 _amount, bytes memory _permitParams) internal {
        DataTypes.PermitParams memory p = abi.decode(_permitParams, (DataTypes.PermitParams));
        ERC20Permit(_asset).permit(_user, address(this), _amount, p.deadline, p.v, p.r, p.s);
    }

    function executeTransferFromPermit2(
        address _permit2,
        address _asset, 
        address _from, 
        address _to, 
        uint256 _amount, 
        bytes memory _permitParams
    ) internal {

        DataTypes.Permit2Params memory p = abi.decode(_permitParams, (DataTypes.Permit2Params));

        IPermit2(_permit2).permitTransferFrom(
            // The permit message.
            IPermit2.PermitTransferFrom({
                permitted: IPermit2.TokenPermissions({
                    token: IERC20(_asset),
                    amount: _amount
                }),
                nonce: p.nonce,
                deadline: p.deadline
            }),
            // The transfer recipient and amount.
            IPermit2.SignatureTransferDetails({
                to: _to,
                requestedAmount: _amount
            }),
            // The owner of the tokens, which must also be
            // the signer of the message, otherwise this call
            // will fail.
            _from,
            // The packed signature that was the result of signing
            // the EIP712 hash of `permit`.
            p.signature
        );

    }
}

