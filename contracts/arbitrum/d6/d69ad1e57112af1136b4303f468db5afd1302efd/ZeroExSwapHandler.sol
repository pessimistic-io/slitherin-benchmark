// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import { CoreSwapHandlerV1 } from "./CoreSwapHandlerV1.sol";
import { ZeroExApiAdapter } from "./ZeroExApiAdapter.sol";
import { CallUtils } from "./BubbleReverts.sol";
import { SwapDeadlineExceeded } from "./DefinitiveErrors.sol";

import { BaseAccessControl, CoreAccessControlConfig } from "./BaseAccessControl.sol";

contract ZeroExSwapHandler is CoreSwapHandlerV1, ZeroExApiAdapter {
    constructor(address _zeroExProxy, address _wethAddress) ZeroExApiAdapter(_zeroExProxy, _wethAddress) {}

    receive() external payable {}

    function decodeParams(bytes memory data) public pure returns (ZeroExSwapParams memory zeroExSwapParams) {
        zeroExSwapParams = abi.decode(data, (ZeroExSwapParams));
    }

    function _performSwap(SwapParams memory params) internal override {
        ZeroExSwapParams memory zeroExSwapParams = decodeParams(params.data);

        if (zeroExSwapParams.deadline < block.timestamp) {
            revert SwapDeadlineExceeded();
        }

        (bool _success, bytes memory _returnBytes) = zeroExAddress.call{ value: msg.value }(zeroExSwapParams.swapData);
        if (!_success) {
            CallUtils.revertFromReturnedData(_returnBytes);
        }
    }

    function _getSpenderAddress(bytes memory) internal view override returns (address) {
        return zeroExAddress;
    }

    // TODO (DEF-916) - Add validation
    function _validatePools(SwapParams memory params, bool) internal view override {
        // _validateZeroExPayload(
        //     params.inputAssetAddress,
        //     params.outputAssetAddress,
        //     msg.sender,
        //     params.inputAmount,
        //     params.minOutputAmount,
        //     params.data
        // );
    }

    /**
     * @notice no implementation because `_validatePools` handles both path and swap validation
     */
    function _validateSwap(SwapParams memory params) internal pure override {}
}

