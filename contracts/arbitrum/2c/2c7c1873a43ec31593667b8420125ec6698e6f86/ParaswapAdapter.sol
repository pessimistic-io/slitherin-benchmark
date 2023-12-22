// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./AdapterBase.sol";

/**
// @title Adapter Contract for Paraswap DEX Aggregator.
// @notice Follows AdapterBase interface.
*/
contract ParaswapAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    address public paraswapTokenTransferProxy;
    address public augustusSwapper;

    /**
    // @dev _paraswapTokenTransferProxy is the adddress that must be approved before calling the swap function
    // @dev _augustusSwapper is the address to which transfer the callData
    */
    constructor(address _dispatcher, address _paraswapTokenTransferProxy, address _augustusSwapper) AdapterBase(_dispatcher) {
        paraswapTokenTransferProxy = _paraswapTokenTransferProxy;
        augustusSwapper = _augustusSwapper;
        feeRateBps = 30;
    }

    function setParaswapAddresses(address _paraswapProxy, address _augustusSwapper) public onlyDispatcher {
        require(_paraswapProxy != address(0) && _augustusSwapper != address(0), "ZERO_ADDRESS_FORBIDDEN");
        paraswapTokenTransferProxy = _paraswapProxy;
        augustusSwapper = _augustusSwapper;
    }

    /**
    // @dev generic function to call Paraswap swap function
    // @param fromUser wallet address requesting the swap
    // @param _inputToken input token address
    // @param _inputTokenAmount input token amount
    // @param _outputToken output token address
    // @param _swapCallData swap callData (intended for 1inch router)
    // @notice funds must be transferred to this contract before calling this function
    // @notice fees will be computed and charged based on the amount of output tokens returned
    // @dev see NATIVE constant from AdapterBase for specifying native token as input or output
    */
    function callAction(
        address fromUser,
        address _inputToken,
        uint256 _inputTokenAmount,
        address _outputToken,
        bytes memory _swapCallData
    ) public payable override onlyDispatcher {
        require(_inputToken != address(0) && _outputToken != address(0), "INVALID_ASSET_ADDRESS");
        bool success;
        bytes memory result;

        if (_inputToken != NATIVE) {
            require(IERC20(_inputToken).balanceOf(address(this)) >= _inputTokenAmount, "UNAVAILABLE_FUNDS");
            IERC20(_inputToken).safeIncreaseAllowance(paraswapTokenTransferProxy, _inputTokenAmount);
            // solhint-disable-next-line
            (success, result) = augustusSwapper.call(_swapCallData);
            IERC20(_inputToken).safeApprove(paraswapTokenTransferProxy, 0);
        } else {
            require(msg.value >= _inputTokenAmount, "VALUE_TOO_LOW");
            // solhint-disable-next-line
            (success, result) = augustusSwapper.call{value: _inputTokenAmount}(_swapCallData);
        }
        require(success, "PARASWAP_SWAP_FAIL");

        (uint256 returnAmount) = abi.decode(result, (uint256));
        uint256 fee = computeFee(returnAmount);

        if (_outputToken != NATIVE) {
            IERC20(_outputToken).safeTransfer(fromUser, returnAmount - fee);
        } else {
            payable(fromUser).transfer(returnAmount - fee);
        }
        emit Swap(fromUser, _inputToken, _inputTokenAmount, _outputToken, returnAmount);
    }
}
