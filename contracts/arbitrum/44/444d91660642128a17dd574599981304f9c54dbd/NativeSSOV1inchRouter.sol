// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {I1inchAggregationRouterV4} from "./I1inchAggregationRouterV4.sol";
import {INativeSSOV} from "./INativeSSOV.sol";

contract NativeSSOV1inchRouter {
    using SafeERC20 for IERC20;

    I1inchAggregationRouterV4 public aggregationRouterV4;
    INativeSSOV public ssov;

    struct PurchaseOption {
        uint256 strikeIndex;
        uint256 amount;
        address to;
    }

    /// @notice Constructor
    /// @param _ssov address of SSOV
    /// @param _aggregationRouterV4 address of 1inch V4 Aggregation Router
    constructor(address _ssov, address payable _aggregationRouterV4) {
        ssov = INativeSSOV(_ssov);
        aggregationRouterV4 = I1inchAggregationRouterV4(_aggregationRouterV4);
    }

    receive() external payable {}

    /// @notice Swap any token to the quote asset, then purchase option
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _params PurchaseOption struct parameters to purchase option
    function swapAndPurchase(
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        PurchaseOption calldata _params
    ) external payable returns (bool) {
        IERC20 tokenFrom = IERC20(_desc.srcToken);
        tokenFrom.safeTransferFrom(msg.sender, address(this), _desc.amount);
        tokenFrom.safeApprove(address(aggregationRouterV4), _desc.amount);

        (uint256 returnAmount, ) = aggregationRouterV4.swap(
            _caller,
            _desc,
            _data
        );

        ssov.purchase{value: returnAmount}(
            _params.strikeIndex,
            _params.amount,
            _params.to
        );

        if (address(this).balance > 0) {
            payable(msg.sender).transfer(address(this).balance);
        }

        return true;
    }

    /// @notice Swap any token to quote asset, then deposit quote
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _strikeIndex strike index to deposit to
    /// @param _to address to deposit on behalf of
    function swapAndDeposit(
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        uint256 _strikeIndex,
        address _to
    ) external payable returns (bool) {
        IERC20 tokenFrom = IERC20(_desc.srcToken);

        tokenFrom.safeTransferFrom(msg.sender, address(this), _desc.amount);
        tokenFrom.safeApprove(address(aggregationRouterV4), _desc.amount);

        (uint256 returnAmount, ) = aggregationRouterV4.swap(
            _caller,
            _desc,
            _data
        );

        ssov.deposit{value: returnAmount}(_strikeIndex, _to);

        return true;
    }

    /// @notice Swap any token to quote asset, then deposit quote
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _strikeIndices indices of strikes to deposit into
    /// @param _amounts amount of native token to deposit into each strike index
    /// @param _to address to deposit on behalf of
    function swapAndDepositMultiple(
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts,
        address _to
    ) external payable returns (bool) {
        IERC20 tokenFrom = IERC20(_desc.srcToken);

        tokenFrom.safeTransferFrom(msg.sender, address(this), _desc.amount);
        tokenFrom.safeApprove(address(aggregationRouterV4), _desc.amount);

        (uint256 returnAmount, ) = aggregationRouterV4.swap(
            _caller,
            _desc,
            _data
        );

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++)
            totalAmount = totalAmount + _amounts[i];

        ssov.depositMultiple{value: totalAmount}(_strikeIndices, _amounts, _to);

        payable(msg.sender).transfer(returnAmount - totalAmount);

        return true;
    }
}

