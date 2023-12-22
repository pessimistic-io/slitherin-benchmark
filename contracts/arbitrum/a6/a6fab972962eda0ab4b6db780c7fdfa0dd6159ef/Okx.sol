// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./BaseSwap.sol";
import "./SafeERC20.sol";
import "./Address.sol";
import "./IERC20Ext.sol";

contract Okx is BaseSwap {
    using SafeERC20 for IERC20Ext;
    using Address for address;
    using SafeMath for uint256;

    address public router;
    address public okxTokenApprove;

    event UpdatedAggregationRouter(address router);
    event UpdatedOkxTokenApprove(address okxTokenApprove);

    constructor(
        address _admin,
        address _router,
        address _okxTokenApprove
    ) BaseSwap(_admin) {
        router = _router;
        okxTokenApprove = _okxTokenApprove;
    }

    function updateAggregationRouter(address _router) external onlyAdmin {
        router = _router;
        emit UpdatedAggregationRouter(router);
    }

    function updatedOkxTokenApprove(address _okxTokenApprove) external onlyAdmin {
        okxTokenApprove = _okxTokenApprove;
        emit UpdatedOkxTokenApprove(okxTokenApprove);
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
    /// Okx API will returns calls neccessary to build tx
    /// tx's calls will be passed by params.extraData
    function swap(SwapParams calldata params)
        external
        payable
        override
        onlyProxyContract
        returns (uint256 destAmount)
    {
        require(params.tradePath.length == 2, "Okx_invalidTradepath");

        safeApproveAllowance(address(okxTokenApprove), IERC20Ext(params.tradePath[0]));

        IERC20Ext actualDest = IERC20Ext(params.tradePath[params.tradePath.length - 1]);
        uint256 destBalanceBefore = getBalance(actualDest, address(this));

        bool etherIn = IERC20Ext(params.tradePath[0]) == ETH_TOKEN_ADDRESS;
        uint256 callValue = etherIn ? params.srcAmount : 0;

        (bool success, ) = router.call{value: callValue}(params.extraArgs);
        require(success, "Okx_invalidExtraArgs");

        uint256 returnAmount = getBalance(actualDest, address(this)).sub(destBalanceBefore);
        return safeTransferTo(payable(params.recipient), actualDest, returnAmount);
    }

    function safeTransferTo(
        address payable to,
        IERC20Ext tokenErc,
        uint256 amount
    ) internal returns (uint256 amountTransferred) {
        if (tokenErc == ETH_TOKEN_ADDRESS) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "transfer failed");
            amountTransferred = amount;
        } else {
            uint256 balanceBefore = tokenErc.balanceOf(to);
            tokenErc.safeTransfer(to, amount);
            amountTransferred = tokenErc.balanceOf(to).sub(balanceBefore);
        }
    }
}

