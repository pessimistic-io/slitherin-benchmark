// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {I1inchAggregationRouterV4} from "./I1inchAggregationRouterV4.sol";
import {IERC20SSOV} from "./IERC20SSOV.sol";

interface ICrv2Pool is IERC20 {
    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount)
        external
        returns (uint256);

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function coins(uint256) external view returns (address);
}

contract Curve2PoolSsovPut1inchRouter {
    using SafeERC20 for IERC20;
    using SafeERC20 for ICrv2Pool;

    I1inchAggregationRouterV4 public aggregationRouterV4;
    ICrv2Pool public crv2Token;
    IERC20 public usdt;
    IERC20 public usdc;

    address public immutable wrappedNativeToken;

    struct PurchaseOption {
        uint256 strikeIndex;
        uint256 amount;
        address to;
    }

    /// @notice Constructor
    /// @param _aggregationRouterV4 address of 1inch V4 Aggregation Router
    /// @param _wrappedNativeToken address of the wrapped native token contract
    /// @param _crv2Token address of 2CRV token
    /// @param _usdc address of USDC
    /// @param _usdt address of USDT
    constructor(
        address payable _aggregationRouterV4,
        address _wrappedNativeToken,
        address _crv2Token,
        address _usdc,
        address _usdt
    ) {
        aggregationRouterV4 = I1inchAggregationRouterV4(_aggregationRouterV4);
        wrappedNativeToken = _wrappedNativeToken;
        crv2Token = ICrv2Pool(_crv2Token);
        usdc = IERC20(_usdc);
        usdt = IERC20(_usdt);
    }

    receive() external payable {
        assert(msg.sender == wrappedNativeToken); // only accept Native token via fallback from the Wrapped Native token contract
    }

    /// @notice Use USDT/USDC to obtain 2pool token and deposit
    /// @param _amount amount of USDT/USDC
    /// @param _tokenAddress address of USDT or USDC
    /// @param _strikeIndices indices of strikes to deposit into
    /// @param _amounts amount of token to deposit into each strike index
    /// @param _to address to deposit on behalf of
    /// @param _ssov address of the ssov
    function swapAndDepositMultipleFromSingle(
        uint256 _amount,
        address _tokenAddress,
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts,
        address _to,
        address _ssov
    ) external returns (bool) {
        IERC20 token = IERC20(_tokenAddress);
        IERC20SSOV ssov = IERC20SSOV(_ssov);
        uint256[2] memory deposits;

        if (address(usdc) == address(token)) deposits = [_amount, 0];
        if (address(usdt) == address(token)) deposits = [0, _amount];

        token.safeTransferFrom(msg.sender, address(this), _amount);
        token.safeIncreaseAllowance(address(crv2Token), _amount);

        uint256 crv2TokenBalance = crv2Token.add_liquidity(deposits, 0);
        crv2Token.safeIncreaseAllowance(address(ssov), crv2TokenBalance);
        ssov.depositMultiple(_strikeIndices, _amounts, _to);

        _transferLeftoverBalance();
        return true;
    }

    /// @notice Use USDT/USDC to obtain 2pool token and purchase
    /// @param _amount amount of USDT/USDC
    /// @param _tokenAddress address of USDT or USDC
    /// @param _params PurchaseOption struct parameters to purchase option
    /// @param _ssov address of the ssov
    function swapAndPurchaseFromSingle(
        uint256 _amount,
        address _tokenAddress,
        PurchaseOption calldata _params,
        address _ssov
    ) external returns (bool) {
        IERC20 token = IERC20(_tokenAddress);
        IERC20SSOV ssov = IERC20SSOV(_ssov);

        uint256[2] memory deposits;

        if (address(usdc) == address(token)) deposits = [_amount, 0];
        if (address(usdt) == address(token)) deposits = [0, _amount];

        token.safeTransferFrom(msg.sender, address(this), _amount);
        token.safeIncreaseAllowance(address(crv2Token), _amount);

        uint256 crv2TokenBalance = crv2Token.add_liquidity(deposits, 0);
        crv2Token.safeIncreaseAllowance(address(ssov), crv2TokenBalance);
        ssov.purchase(_params.strikeIndex, _params.amount, _params.to);

        _transferLeftoverBalance();
        return true;
    }

    /// @notice Swap any token to USDT/USDC, then obtain 2pool token and purchase
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _params PurchaseOption struct parameters to purchase option
    /// @param _ssov address of the ssov
    function swapAndPurchase(
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        PurchaseOption calldata _params,
        address _ssov
    ) external returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssov);

        IERC20 tokenFrom = IERC20(_desc.srcToken);
        IERC20 tokenTo = IERC20(_desc.dstToken);
        uint256[2] memory deposits;

        tokenFrom.safeTransferFrom(msg.sender, address(this), _desc.amount);
        tokenFrom.safeApprove(address(aggregationRouterV4), _desc.amount);
        (uint256 returnAmount, ) = aggregationRouterV4.swap(
            _caller,
            _desc,
            _data
        );

        tokenTo.safeIncreaseAllowance(address(crv2Token), returnAmount);

        if (address(usdc) == address(tokenTo)) deposits = [returnAmount, 0];
        if (address(usdt) == address(tokenTo)) deposits = [0, returnAmount];

        uint256 crv2TokenBalance = crv2Token.add_liquidity(deposits, 0);
        crv2Token.safeIncreaseAllowance(address(ssov), crv2TokenBalance);

        ssov.purchase(_params.strikeIndex, _params.amount, _params.to);

        _transferLeftoverBalance();
        return true;
    }

    /// @notice Swap native token to USDT/USDC, then obtain 2pool token and purchase
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _params PurchaseOption struct parameters to purchase option
    /// @param _ssov address of the ssov
    function swapNativeAndPurchase(
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        PurchaseOption calldata _params,
        address _ssov
    ) external payable returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssov);

        IERC20 tokenTo = IERC20(_desc.dstToken);
        uint256[2] memory deposits;

        (uint256 returnAmount, ) = aggregationRouterV4.swap{value: msg.value}(
            _caller,
            _desc,
            _data
        );

        tokenTo.safeIncreaseAllowance(address(crv2Token), returnAmount);

        if (address(usdc) == address(tokenTo)) deposits = [returnAmount, 0];
        if (address(usdt) == address(tokenTo)) deposits = [0, returnAmount];

        uint256 crv2TokenBalance = crv2Token.add_liquidity(deposits, 0);
        crv2Token.safeIncreaseAllowance(address(ssov), crv2TokenBalance);

        ssov.purchase(_params.strikeIndex, _params.amount, _params.to);

        _transferLeftoverBalance();
        return true;
    }

    /// @notice Swap any token to USDT/USDC, then obtain 2pool token and deposit
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _strikeIndex strike index to deposit to
    /// @param _to address to deposit on behalf of
    /// @param _ssov address of the ssov
    function swapAndDeposit(
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        uint256 _strikeIndex,
        address _to,
        address _ssov
    ) external returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssov);

        IERC20 tokenFrom = IERC20(_desc.srcToken);
        IERC20 tokenTo = IERC20(_desc.dstToken);
        uint256[2] memory deposits;

        tokenFrom.safeTransferFrom(msg.sender, address(this), _desc.amount);
        tokenFrom.safeApprove(address(aggregationRouterV4), _desc.amount);

        (uint256 returnAmount, ) = aggregationRouterV4.swap(
            _caller,
            _desc,
            _data
        );

        tokenTo.safeIncreaseAllowance(address(crv2Token), returnAmount);

        if (address(usdc) == address(tokenTo)) deposits = [returnAmount, 0];
        if (address(usdt) == address(tokenTo)) deposits = [0, returnAmount];

        uint256 crv2TokenBalance = crv2Token.add_liquidity(deposits, 0);
        crv2Token.safeIncreaseAllowance(address(ssov), crv2TokenBalance);

        ssov.deposit(_strikeIndex, crv2TokenBalance, _to);

        _transferLeftoverBalance();
        return true;
    }

    /// @notice Swap any token to USDT/USDC, then obtain 2pool token and deposit
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _strikeIndices indices of strikes to deposit into
    /// @param _amounts amount of token to deposit into each strike index
    /// @param _to address to deposit on behalf of
    /// @param _ssov address of the ssov
    function swapAndDepositMultiple(
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts,
        address _to,
        address _ssov
    ) external returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssov);

        IERC20 tokenFrom = IERC20(_desc.srcToken);
        IERC20 tokenTo = IERC20(_desc.dstToken);
        uint256[2] memory deposits;

        tokenFrom.safeTransferFrom(msg.sender, address(this), _desc.amount);
        tokenFrom.safeApprove(address(aggregationRouterV4), _desc.amount);

        (uint256 returnAmount, ) = aggregationRouterV4.swap(
            _caller,
            _desc,
            _data
        );

        tokenTo.safeIncreaseAllowance(address(crv2Token), returnAmount);

        if (address(usdc) == address(tokenTo)) deposits = [returnAmount, 0];
        if (address(usdt) == address(tokenTo)) deposits = [0, returnAmount];

        uint256 crv2TokenBalance = crv2Token.add_liquidity(deposits, 0);
        crv2Token.safeIncreaseAllowance(address(ssov), crv2TokenBalance);
        ssov.depositMultiple(_strikeIndices, _amounts, _to);

        _transferLeftoverBalance();
        return true;
    }

    /// @notice Swap native token to USDT/USDC, then obtain 2pool token and deposit
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _strikeIndex strike index to deposit to
    /// @param _to address to deposit on behalf of
    /// @param _ssov address of the ssov
    function swapNativeAndDeposit(
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        uint256 _strikeIndex,
        address _to,
        address _ssov
    ) external payable returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssov);

        IERC20 tokenTo = IERC20(_desc.dstToken);
        uint256[2] memory deposits;

        (uint256 returnAmount, ) = aggregationRouterV4.swap{value: msg.value}(
            _caller,
            _desc,
            _data
        );

        tokenTo.safeIncreaseAllowance(address(crv2Token), returnAmount);

        if (address(usdc) == address(tokenTo)) deposits = [returnAmount, 0];
        if (address(usdt) == address(tokenTo)) deposits = [0, returnAmount];

        uint256 crv2TokenBalance = crv2Token.add_liquidity(deposits, 0);
        crv2Token.safeIncreaseAllowance(address(ssov), crv2TokenBalance);
        ssov.deposit(_strikeIndex, crv2TokenBalance, _to);

        _transferLeftoverBalance();
        return true;
    }

    /// @notice Swap native token to USDT/USDC, then obtain 2pool token and deposit
    /// @param _caller aggregation executor that executes calls described in data
    /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
    /// @param _data encoded calls that caller should execute in between of swaps
    /// @param _strikeIndices indices of strikes to deposit into
    /// @param _amounts amount of token to deposit into each strike index
    /// @param _to address to deposit on behalf of
    /// @param _ssov address of the ssov
    function swapNativeAndDepositMultiple(
        address _caller,
        I1inchAggregationRouterV4.SwapDescription memory _desc,
        bytes calldata _data,
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts,
        address _to,
        address _ssov
    ) external payable returns (bool) {
        IERC20SSOV ssov = IERC20SSOV(_ssov);

        IERC20 tokenTo = IERC20(_desc.dstToken);
        uint256[2] memory deposits;

        (uint256 returnAmount, ) = aggregationRouterV4.swap{value: msg.value}(
            _caller,
            _desc,
            _data
        );

        tokenTo.safeIncreaseAllowance(address(crv2Token), returnAmount);

        if (address(usdc) == address(tokenTo)) deposits = [returnAmount, 0];
        if (address(usdt) == address(tokenTo)) deposits = [0, returnAmount];

        uint256 crv2TokenBalance = crv2Token.add_liquidity(deposits, 0);
        crv2Token.safeIncreaseAllowance(address(ssov), crv2TokenBalance);
        ssov.depositMultiple(_strikeIndices, _amounts, _to);

        _transferLeftoverBalance();
        return true;
    }

    /// @notice transfer leftover balance
    function _transferLeftoverBalance() internal returns (bool) {
        uint256 crv2TokenBalance = crv2Token.balanceOf(address(this));
        uint256 nativeTokenBalance = address(this).balance;

        if (crv2TokenBalance > 0)
            crv2Token.safeTransfer(msg.sender, crv2TokenBalance);

        if (nativeTokenBalance > 0)
            payable(msg.sender).transfer(nativeTokenBalance);

        return true;
    }
}

