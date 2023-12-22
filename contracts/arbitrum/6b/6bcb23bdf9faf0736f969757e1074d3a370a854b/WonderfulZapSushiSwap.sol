// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./IWonderfulChef.sol";
import "./Babylonian.sol";

/*
    WonderfulZap is a ZapperFi's simplified version of zapper contract which will:
    1. use ETH to swap to target token
    2. make LP between ETH and target token
    3. add into WonderfulChef farm
*/
contract WonderfulZapSushiSwap is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct ZapInfo {
        uint256 pid;
        IERC20 token;
        bool inactive;
    }

    ZapInfo[] public zaps;
    IWonderfulChef public wonderfulChef;
    IUniswapV2Router02 public uniRouter;

    address public constant wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH (Arb1)

    constructor(address _wonderfulChef, address _uniRouter) {
        require(_wonderfulChef != address(0), "Zap::constructor: Invalid address");
        require(_uniRouter != address(0), "Zap::constructor: Invalid address");
        wonderfulChef = IWonderfulChef(_wonderfulChef);
        uniRouter = IUniswapV2Router02(_uniRouter);
    }

    // ========= MUTATIVE FUNCTION ==============

    /// @notice Zap function to receive ETH, swap for opposing token,
    /// add liquidity, and deposit LP to farm
    /// @param _zapId: Id of the zap configuration
    /// @param _minLiquidity: Minimum amount of LP received
    /// @param _transferResidual: Flag to determine to transfer dust back to user
    function zap(
        uint256 _zapId,
        uint256 _minLiquidity,
        bool _transferResidual
    ) external payable nonReentrant {
        ZapInfo memory _info = zaps[_zapId];
        require(!_info.inactive, "Zap::zap: Zap configuration is inactive");
        uint256 _ethIn = msg.value;

        address _lp = address(wonderfulChef.lpToken(_info.pid));
        require(_lp != address(0), "Zap::zap: Invalid LP");

        // STEP 1: Swap or Mint token
        (uint256 _ethAmtToSwap, uint256 _tokenAmtToAddLP) = swap(_lp, _ethIn, address(_info.token));

        // STEP 2: Add liquditiy
        uint256 _ethAmtToAddLP = _ethIn - _ethAmtToSwap;
        approveToken(address(_info.token), address(uniRouter), _tokenAmtToAddLP);
        (uint256 _tokenAmtUsedInLp, uint256 _ethAmtUsedInLp, uint256 _liquidity) = uniRouter
            .addLiquidityETH{value: _ethAmtToAddLP}(
            address(_info.token),
            _tokenAmtToAddLP,
            1,
            1,
            address(this),
            block.timestamp
        );
        require(_liquidity >= _minLiquidity, "Zap::zap: Slippage. < minLiquidity");

        // STEP 3: Deposit LP to Farm
        approveToken(_lp, address(wonderfulChef), _liquidity);
        wonderfulChef.deposit(_info.pid, _liquidity, msg.sender);

        // STEP 4: Clean up dust
        if (_transferResidual) {
            if (_tokenAmtToAddLP > _tokenAmtUsedInLp) {
                _info.token.safeTransfer(msg.sender, _tokenAmtToAddLP - _tokenAmtUsedInLp);
            }
            if (_ethAmtToAddLP > _ethAmtUsedInLp) {
                Address.sendValue(payable(msg.sender), _ethAmtToAddLP - _ethAmtUsedInLp);
            }
        }

        emit Zapped(_zapId, _ethIn, _liquidity);
    }

    /// @notice fallback for payable -> required to receive WETH
    receive() external payable {}

    /// @notice Swap internal function to swap from ETH to target Token with calculation
    /// for the appropriate amount of ETH will be used to swap in order to minimize dust
    /// @param _lp: address of the LP pair between WETH and Token
    /// @param _ethIn: Amount of ETH input
    /// @param _token: address of target Token
    function swap(
        address _lp,
        uint256 _ethIn,
        address _token
    ) internal returns (uint256 _ethAmtToSwap, uint256 _tokenAmtReceived) {
        address _token0 = IUniswapV2Pair(_lp).token0();
        (uint256 _res0, uint256 _res1, ) = IUniswapV2Pair(_lp).getReserves();

        if (_token == _token0) {
            _ethAmtToSwap = calculateSwapInAmount(_res1, _ethIn);
        } else {
            _ethAmtToSwap = calculateSwapInAmount(_res0, _ethIn);
        }

        if (_ethAmtToSwap <= 0) _ethAmtToSwap = _ethIn / 2;
        _tokenAmtReceived = doSwapETH(_token, _ethAmtToSwap);
    }

    /// @notice Swap internal function to swap from ETH to target Token
    /// @param _toToken: address of target Token
    /// @param _ethAmt: Amount of ETH input
    function doSwapETH(address _toToken, uint256 _ethAmt)
        internal
        returns (uint256 _tokenReceived)
    {
        address[] memory _path = new address[](2);
        _path[0] = wethAddress;
        _path[1] = _toToken;

        _tokenReceived = uniRouter.swapExactETHForTokens{value: _ethAmt}(
            1,
            _path,
            address(this),
            block.timestamp
        )[_path.length - 1];

        require(_tokenReceived > 0, "Zap::doSwapETH: Error Swapping Tokens 2");
    }

    /// @notice Safe approve spending of an token for an address
    /// @param _token: address of target Token
    /// @param _spender: address of spender
    /// @param _amount: Amount of token can be spent
    function approveToken(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20 _erc20Token = IERC20(_token);
        _erc20Token.safeApprove(_spender, 0);
        _erc20Token.safeApprove(_spender, _amount);
    }

    /// @notice calculate amount to swap just enough so least dust will be leftover when adding liquidity
    /// copied from zapper.fi contract. Assuming 0.2% swap fee
    /// @param _reserveIn: Amount of Reserve for the target token
    /// @param _tokenIn: Amount of total input
    function calculateSwapInAmount(uint256 _reserveIn, uint256 _tokenIn)
        internal
        pure
        returns (uint256)
    {
        return
            (Babylonian.sqrt(_reserveIn * ((_tokenIn * 3992000) + (_reserveIn * 3992004))) -
                (_reserveIn * 1998)) / 1996;
    }

    // ========= RESTRICTIVE FUNCTIONS ==============

    /// @notice Add new zap configuration
    /// @param _token: address of target Token
    /// @param _pid: pid in the target farm
    function addZap(address _token, uint256 _pid) external onlyOwner returns (uint256 _zapId) {
        require(_token != address(0), "Zap::addZap: Invalid address");
        zaps.push(ZapInfo({token: IERC20(_token), pid: _pid, inactive: false}));
        _zapId = zaps.length - 1;

        emit ZapAdded(_zapId, _token, _pid);
    }

    /// @notice Deactivate a Zap configuration
    /// @param _zapId: Id of the zap configuration
    function removeZap(uint256 _zapId) external onlyOwner {
        require(zaps.length > _zapId, "Zap::removeZap: Invalid zapId");
        ZapInfo storage info = zaps[_zapId];
        info.inactive = true;

        emit ZapRemoved(_zapId);
    }

    // ========= EVENTS ==============
    event ZapAdded(uint256 _id, address _token, uint256 _pid);
    event ZapRemoved(uint256 _id);
    event Zapped(uint256 _zapId, uint256 _amount, uint256 _liquidity);
}
