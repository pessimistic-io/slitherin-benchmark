//SPDX-License-Identifier: ISC

pragma solidity ^0.8.13;

import {IStargateReceiver} from "./IStargateReceiver.sol";
import {IStargateRouter} from "./IStargateRouter.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IArbitrumSwaps} from "./IArbitrumSwaps.sol";

abstract contract StargateArbitrum is IStargateReceiver {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    ///@notice address of the stargate router
    IStargateRouter public immutable stargateRouter;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event ReceivedOnDestination(address indexed token, uint256 amountLD, bool failed, bool dustSent);
    event FeePaid(address _token, uint256 _fee);

    error NotStgRouter();
    error MustBeGt0();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(IStargateRouter _stargateRouter) {
        stargateRouter = _stargateRouter;
    }

    ///@notice struct to define parameters needed for the swap.
    struct StargateParams {
        uint16 dstChainId; // stargate dst chain id
        address token; // token getting bridged
        uint256 srcPoolId; // stargate src pool id
        uint256 dstPoolId; // stargate dst pool id
        uint256 amount; // amount to bridge
        uint256 amountMin; // amount to bridge minimum
        uint256 dustAmount; // native token to be received on dst chain
        address receiver; // Mugen contract on dst chain
        address to; // receiver bridge token incase of transaction reverts on dst chain
        uint256 gas; // extra gas to be sent for dst chain operations
        bytes32 srcContext; // random bytes32 as source context
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @param params parameters for the stargate router defined in StargateParams
    /// @param stepsDst an arrat of steps to be performed on the dst chain
    /// @param dataDst an array of data to be performed on the dst chain
    function stargateSwap(StargateParams memory params, uint8[] memory stepsDst, bytes[] memory dataDst) internal {
        if (msg.value <= 0) revert MustBeGt0();
        bytes memory payload = abi.encode(params.to, stepsDst, dataDst);

        params.amount = params.amount != 0 ? params.amount : IERC20(params.token).balanceOf(address(this));
        IERC20(params.token).safeIncreaseAllowance(address(stargateRouter), params.amount);
        IStargateRouter(stargateRouter).swap{value: address(this).balance}(
            params.dstChainId,
            params.srcPoolId,
            params.dstPoolId,
            payable(address(this)),
            params.amount,
            params.amountMin,
            IStargateRouter.lzTxObj(params.gas, params.dustAmount, abi.encodePacked(params.receiver)),
            abi.encodePacked(params.receiver),
            payload
        );
    }

    function calculateFee(uint256 amount) internal pure returns (uint256 fee) {
        fee = amount - ((amount * 9995) / 1e4);
    }

    /*//////////////////////////////////////////////////////////////
                               STARGATE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @param _token The token contract on the local chain
    /// @param amountLD The qty of local _token contract tokens
    /// @param _payload The bytes containing the toAddress
    function sgReceive(uint16, bytes memory, uint256, address _token, uint256 amountLD, bytes memory _payload)
        external
        override
    {
        if (msg.sender != address(stargateRouter)) revert NotStgRouter();

        (address to, uint8[] memory steps, bytes[] memory data) = abi.decode(_payload, (address, uint8[], bytes[]));
        bool failed;

        try IArbitrumSwaps(payable(address(this))).arbitrumSwaps{gas: 200000}(steps, data) {}
        catch (bytes memory) {
            IERC20(_token).safeTransfer(to, amountLD);
            failed = true;
        }
        bool dustSent;
        if (address(this).balance > 0) {
            (dustSent,) = to.call{value: address(this).balance}("");
        }
        emit ReceivedOnDestination(_token, amountLD, failed, dustSent);
    }
}

