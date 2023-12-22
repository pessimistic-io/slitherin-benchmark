// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {GelatoBytes} from "./GelatoBytes.sol";

contract ExecFacet {
    using GelatoBytes for bytes;

    event LogExecSuccess(
        address indexed executor,
        address indexed service,
        bool success
    );

    function exec(
        address _service,
        bytes calldata _data,
        address _creditToken
    ) external {
        _creditToken;

        (bool success, bytes memory returndata) = _service.call(_data);
        if (!success) returndata.revertWithError("ExecFacet.exec:");

        emit LogExecSuccess(msg.sender, _service, success);
    }

    /// @dev dummy for now to keep as a placeholder on the contract interface
    function estimateExecGasDebit(
        address _service,
        bytes calldata _data,
        address _creditToken
    ) external returns (uint256 gasDebitInETH, uint256 gasDebitInCreditToken) {
        _creditToken;

        (bool success, bytes memory returndata) = _service.call(_data);
        if (!success) returndata.revertWithError("ExecFacet.exec:");

        gasDebitInETH = 1;
        gasDebitInCreditToken = 1;
    }

    function concurrentCanExec(uint256) external pure returns (bool) {
        return true;
    }
}

