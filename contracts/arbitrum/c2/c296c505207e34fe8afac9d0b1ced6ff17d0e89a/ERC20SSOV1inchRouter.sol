// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {I1inchAggregationRouterV4} from "./I1inchAggregationRouterV4.sol";
import {IERC20SSOV} from "./IERC20SSOV.sol";

contract ERC20SSOV1inchRouter {
    using SafeERC20 for IERC20;

    I1inchAggregationRouterV4 public aggregationRouterV4;

    address public immutable wrappedNativeToken;

    struct PurchaseOption {
        uint256 strikeIndex;
        uint256 amount;
        address to;
    }

    /// @notice Constructor
    /// @param _aggregationRouterV4 address of 1inch V4 Aggregation Router
    /// @param _wrappedNativeToken address of the wrapped native token contract
    constructor(
        address payable _aggregationRouterV4,
        address _wrappedNativeToken
    ) {
        aggregationRouterV4 = I1inchAggregationRouterV4(_aggregationRouterV4);
        wrappedNativeToken = _wrappedNativeToken;
    }

    receive() external payable {
        assert(msg.sender == wrappedNativeToken); // only accept Native token via fallback from the Wrapped Native token contract
    }

    /// @notice Swap any token to the quote asset, then purchase option
    /// @param _ssovAddress address of the SSOV
    /// @param _ssovTokenAddress address of the SSOV token
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _params PurchaseOption struct parameters to purchase option
    function swapAndPurchase(
        address _ssovAddress,
        address _ssovTokenAddress,
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        PurchaseOption calldata _params
    ) external returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssovAddress);
        IERC20 ssovToken = IERC20(_ssovTokenAddress);
        IERC20 tokenFrom = IERC20(_desc.srcToken);
        tokenFrom.safeTransferFrom(msg.sender, address(this), _desc.amount);
        tokenFrom.safeApprove(address(aggregationRouterV4), _desc.amount);
        (uint256 returnAmount, ) = aggregationRouterV4.swap(
            _caller,
            _desc,
            _data
        );
        ssovToken.safeIncreaseAllowance(address(ssov), returnAmount);
        ssov.purchase(_params.strikeIndex, _params.amount, _params.to);
        _transferLeftoverBalance(_ssovTokenAddress);
        return true;
    }

    /// @notice Swap native token to the quote asset, then purchase option
    /// @param _ssovAddress address of the SSOV
    /// @param _ssovTokenAddress address of the SSOV token
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _params PurchaseOption struct parameters to purchase option
    function swapNativeAndPurchase(
        address _ssovAddress,
        address _ssovTokenAddress,
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        PurchaseOption calldata _params
    ) external payable returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssovAddress);
        IERC20 ssovToken = IERC20(_ssovTokenAddress);
        (uint256 returnAmount, ) = aggregationRouterV4.swap{value: msg.value}(
            _caller,
            _desc,
            _data
        );
        ssovToken.safeIncreaseAllowance(address(ssov), returnAmount);
        ssov.purchase(_params.strikeIndex, _params.amount, _params.to);
        _transferLeftoverBalance(_ssovTokenAddress);
        return true;
    }

    /// @notice Swap any token to quote asset, then deposit quote
    /// @param _ssovAddress address of the SSOV
    /// @param _ssovTokenAddress address of the SSOV token
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _strikeIndex strike index to deposit to
    /// @param _to address to deposit on behalf of
    function swapAndDeposit(
        address _ssovAddress,
        address _ssovTokenAddress,
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        uint256 _strikeIndex,
        address _to
    ) external returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssovAddress);
        IERC20 ssovToken = IERC20(_ssovTokenAddress);
        IERC20 tokenFrom = IERC20(_desc.srcToken);

        tokenFrom.safeTransferFrom(msg.sender, address(this), _desc.amount);
        tokenFrom.safeApprove(address(aggregationRouterV4), _desc.amount);

        (uint256 returnAmount, ) = aggregationRouterV4.swap(
            _caller,
            _desc,
            _data
        );

        ssovToken.safeIncreaseAllowance(address(ssov), returnAmount);
        ssov.deposit(_strikeIndex, returnAmount, _to);
        return true;
    }

    /// @notice Swap any token to quote asset, then deposit quote
    /// @param _ssovAddress address of the SSOV
    /// @param _ssovTokenAddress address of the SSOV token
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _strikeIndices indices of strikes to deposit into
    /// @param _amounts amount of token to deposit into each strike index
    /// @param _to address to deposit on behalf of
    function swapAndDepositMultiple(
        address _ssovAddress,
        address _ssovTokenAddress,
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts,
        address _to
    ) external returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssovAddress);
        IERC20 ssovToken = IERC20(_ssovTokenAddress);
        IERC20 tokenFrom = IERC20(_desc.srcToken);

        tokenFrom.safeTransferFrom(msg.sender, address(this), _desc.amount);
        tokenFrom.safeApprove(address(aggregationRouterV4), _desc.amount);

        (uint256 returnAmount, ) = aggregationRouterV4.swap(
            _caller,
            _desc,
            _data
        );

        ssovToken.safeIncreaseAllowance(address(ssov), returnAmount);
        ssov.depositMultiple(_strikeIndices, _amounts, _to);

        _transferLeftoverBalance(_ssovTokenAddress);
        return true;
    }

    /// @notice Swap native token to the quote asset, then deposit quote
    /// @param _ssovAddress address of the SSOV
    /// @param _ssovTokenAddress address of the SSOV token
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _strikeIndex strike index to deposit to
    /// @param _to address to deposit on behalf of
    function swapNativeAndDeposit(
        address _ssovAddress,
        address _ssovTokenAddress,
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        uint256 _strikeIndex,
        address _to
    ) external payable returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssovAddress);
        IERC20 ssovToken = IERC20(_ssovTokenAddress);

        (uint256 returnAmount, ) = aggregationRouterV4.swap{value: msg.value}(
            _caller,
            _desc,
            _data
        );

        ssovToken.safeIncreaseAllowance(address(ssov), returnAmount);
        ssov.deposit(_strikeIndex, returnAmount, _to);

        return true;
    }

    /// @notice Swap native token to the quote asset, then deposit quote
    /// @param _ssovAddress address of the SSOV
    /// @param _ssovTokenAddress address of the SSOV token
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _strikeIndices indices of strikes to deposit into
    /// @param _amounts amount of token to deposit into each strike index
    /// @param _to address to deposit on behalf of
    function swapNativeAndDepositMultiple(
        address _ssovAddress,
        address _ssovTokenAddress,
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts,
        address _to
    ) external payable returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssovAddress);
        IERC20 ssovToken = IERC20(_ssovTokenAddress);
        (uint256 returnAmount, ) = aggregationRouterV4.swap{value: msg.value}(
            _caller,
            _desc,
            _data
        );

        ssovToken.safeIncreaseAllowance(address(ssov), returnAmount);
        ssov.depositMultiple(_strikeIndices, _amounts, _to);

        _transferLeftoverBalance(_ssovTokenAddress);
        return true;
    }

    /// @notice transfer leftover balance to be used for premium
    function _transferLeftoverBalance(address _ssovTokenAddress)
        internal
        returns (bool)
    {
        IERC20 ssovToken = IERC20(_ssovTokenAddress);
        if (ssovToken.balanceOf(address(this)) > 0) {
            ssovToken.safeTransfer(
                msg.sender,
                ssovToken.balanceOf(address(this))
            );
        }
        return true;
    }
}

