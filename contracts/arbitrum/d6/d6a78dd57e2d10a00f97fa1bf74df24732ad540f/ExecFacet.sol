// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {LibExec} from "./LibExec.sol";
import {GelatoBytes} from "./GelatoBytes.sol";
import {getBalance} from "./FUtils.sol";
import {NATIVE_TOKEN} from "./CTokens.sol";

contract ExecFacet {
    using LibExec for address;
    using GelatoBytes for bytes;

    event LogExecSuccess(
        address indexed executor,
        address indexed service,
        bool indexed wasExecutorPaid,
        address creditToken,
        uint256 credit,
        uint256 creditInNativeToken
    );

    // ################ Callable by Executor ################
    // solhint-disable-next-line code-complexity, function-max-lines
    function exec(
        address _service,
        bytes calldata _data,
        address _creditToken
    )
        external
        returns (
            uint256 credit,
            uint256 creditInNativeToken,
            uint256 gasDebitInNativeToken,
            uint256 estimatedGasUsed
        )
    {
        uint256 startGas = gasleft();

        require(msg.sender.isExecutor(), "ExecFacet.exec: onlyExecutors");

        uint256 preCreditTokenBalance = getBalance(_creditToken, address(this));

        (bool success, bytes memory returndata) = _service.call(_data);
        if (!success) returndata.revertWithError("ExecFacet.exec:");

        uint256 postCreditTokenBalance = getBalance(
            _creditToken,
            address(this)
        );

        credit = postCreditTokenBalance - preCreditTokenBalance;

        if (_creditToken == NATIVE_TOKEN) creditInNativeToken = credit;

        if (creditInNativeToken > 0)
            (success, ) = msg.sender.call{value: creditInNativeToken}("");

        gasDebitInNativeToken; // silence warning (var not needed)

        emit LogExecSuccess(
            msg.sender,
            _service,
            creditInNativeToken > 0 ? success : false,
            _creditToken,
            credit,
            creditInNativeToken
        );

        estimatedGasUsed = startGas - gasleft();
    }
}

