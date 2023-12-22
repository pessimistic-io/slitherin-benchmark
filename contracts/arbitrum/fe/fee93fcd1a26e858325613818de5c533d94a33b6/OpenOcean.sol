// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./BaseSwap.sol";
import "./SafeERC20.sol";
import "./Address.sol";
import "./IERC20Ext.sol";
import "./IOpenOceanRouter.sol";

contract OpenOcean is BaseSwap {
    using SafeERC20 for IERC20Ext;
    using Address for address;

    IOpenOceanRouter public router;

    event UpdatedAggregationRouter(IOpenOceanRouter router);

    constructor(address _admin, IOpenOceanRouter _router) BaseSwap(_admin) {
        router = _router;
    }

    function updateAggregationRouter(IOpenOceanRouter _router) external onlyAdmin {
        router = _router;
        emit UpdatedAggregationRouter(router);
    }

    /// @dev get expected return and conversion rate if using a Uni router
    function getExpectedReturn(GetExpectedReturnParams calldata params)
        external
        view
        override
        onlyProxyContract
        returns (uint256 destAmount)
    {
        require(false, "getExpectedReturn_notSupported");
    }

    function getExpectedReturnWithImpact(GetExpectedReturnParams calldata params)
        external
        view
        override
        onlyProxyContract
        returns (uint256 destAmount, uint256 priceImpact)
    {
        require(false, "getExpectedReturn_notSupported");
    }

    function getExpectedIn(GetExpectedInParams calldata params)
        external
        view
        override
        onlyProxyContract
        returns (uint256 srcAmount)
    {
        require(false, "getExpectedIn_notSupported");
    }

    function getExpectedInWithImpact(GetExpectedInParams calldata params)
        external
        view
        override
        onlyProxyContract
        returns (uint256 srcAmount, uint256 priceImpact)
    {
        require(false, "getExpectedIn_notSupported");
    }

    /// @dev swap token
    /// @notice
    /// openOcean API will returns calls neccessary to build tx
    /// tx's calls will be passed by params.extraData
    function swap(SwapParams calldata params)
        external
        payable
        override
        onlyProxyContract
        returns (uint256 destAmount)
    {
        require(params.tradePath.length == 2, "openOcean_invalidTradepath");

        safeApproveAllowance(address(router), IERC20Ext(params.tradePath[0]));

        bytes4 methodId = params.extraArgs[0] |
            (bytes4(params.extraArgs[1]) >> 8) |
            (bytes4(params.extraArgs[2]) >> 16) |
            (bytes4(params.extraArgs[3]) >> 24);

        if (methodId == IOpenOceanRouter.swap.selector) {
            return doSwap(params);
        }

        require(false, "openOcean_invalidExtraArgs");
    }

    /// @dev called when openOcean API returns method AggregationRouter.swap
    /// @notice AggregationRouter.swap method used a custom calldata.
    /// Since we don't know what included in that calldata, backend must take into account fee
    /// when calling openOcean API
    function doSwap(SwapParams calldata params) private returns (uint256 destAmount) {
        uint256 callValue;
        if (params.tradePath[0] == address(ETH_TOKEN_ADDRESS)) {
            callValue = params.srcAmount;
        } else {
            callValue = 0;
        }

        address caller;
        IOpenOceanRouter.SwapDescription memory desc;
        IOpenOceanRouter.CallDescription[] memory calls;

        (caller, desc, calls) = abi.decode(
            params.extraArgs[4:],
            (address, IOpenOceanRouter.SwapDescription, IOpenOceanRouter.CallDescription[])
        );

        destAmount = router.swap{value: callValue}(
            caller,
            IOpenOceanRouter.SwapDescription({
                srcToken: desc.srcToken,
                dstToken: desc.dstToken,
                srcReceiver: desc.srcReceiver,
                dstReceiver: params.recipient,
                amount: params.srcAmount,
                minReturnAmount: params.minDestAmount,
                guaranteedAmount: params.minDestAmount,
                flags: desc.flags,
                referrer: desc.referrer,
                permit: desc.permit
            }),
            calls
        );
    }
}

