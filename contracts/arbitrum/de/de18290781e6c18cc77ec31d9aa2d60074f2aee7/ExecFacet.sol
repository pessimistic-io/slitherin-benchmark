// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {LibExecAccess} from "./LibExecAccess.sol";
import {GelatoBytes} from "./GelatoBytes.sol";
import {_getBalance} from "./FUtils.sol";

contract ExecFacet {
    using LibExecAccess for address;
    using GelatoBytes for bytes;

    event LogExecSuccess(
        address indexed executor,
        address indexed service,
        address indexed creditToken,
        uint256 credit,
        uint256 gasDebitInNativeToken,
        uint256 gasDebitInCreditToken
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
            uint256 gasDebitInNativeToken,
            uint256 gasDebitInCreditToken,
            uint256 estimatedGasUsed
        )
    {
        uint256 startGas = gasleft();

        require(msg.sender.isExecutor(), "ExecFacet.exec: onlyExecutors");

        credit = _execServiceCall(_service, _data, _creditToken);

        emit LogExecSuccess(
            msg.sender,
            _service,
            _creditToken,
            credit,
            gasDebitInNativeToken,
            gasDebitInCreditToken
        );

        estimatedGasUsed = startGas - gasleft();
    }

    function _execServiceCall(
        address _service,
        bytes calldata _data,
        address _creditToken
    ) internal returns (uint256 credit) {
        uint256 preCreditTokenBalance = _getBalance(
            _creditToken,
            address(this)
        );

        (bool success, bytes memory returndata) = _service.call(_data);
        if (!success) returndata.revertWithError("ExecFacet._execServiceCall:");

        uint256 postCreditTokenBalance = _getBalance(
            _creditToken,
            address(this)
        );

        credit = postCreditTokenBalance - preCreditTokenBalance;
    }
}

