// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Permit} from "./draft-ERC20Permit.sol";

import "./console.sol";

library LibPermit {

    struct PermitParams {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function executePermit(
        address _user,
        address _asset,
        uint256 _amount,
        bytes memory _permitParams
    ) internal {
        PermitParams memory p = abi.decode(_permitParams, (PermitParams));
        ERC20Permit(_asset).permit(
            _user,
            address(this),
            _amount,
            p.deadline,
            p.v,
            p.r,
            p.s
        );
    }
}

