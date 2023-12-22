//SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
pragma abicoder v2;

import "./IUniswapV3Pool.sol";
// import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./INonfungiblePositionManager.sol";
import "./TickMath.sol";
import "./OracleLibrary.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
// import "forge-std/console2.sol";

contract LiquidityManager is Ownable{
    using SafeERC20 for IERC20;
    using OracleLibrary for IUniswapV3Pool;

    address public immutable token0;
    address public immutable token1;
    uint24 public immutable poolFee;
    int24 public range;
    uint256 public slippage; //%
    uint256 public amount0Desired;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    IUniswapV3Pool public immutable pool;
    uint256 public tokenId;

    constructor(
        address _token0,
        address _token1,
        uint24 _poolFee,
        int24 _range,
        uint256 _slippage,
        uint256 _amount0Desired,
        address _positionManager,
        address _pool
    ) {
        token0 = _token0;
        token1 = _token1;
        poolFee = _poolFee;
        range = _range;
        slippage = _slippage;
        amount0Desired = _amount0Desired;
        nonfungiblePositionManager = INonfungiblePositionManager(_positionManager);
        pool = IUniswapV3Pool(_pool);
    }

    /// @return _tokenId The id of the newly minted ERC721
    /// @return liquidity The amount of liquidity for the position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mintNewPosition()
        external
        onlyOwner
        returns (
            uint256 _tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        int24 _currentTick = int24(getCurrentTick());
        int24 _SpacedBase = _currentTick / pool.tickSpacing();
        //round off
        if(_currentTick % pool.tickSpacing() > pool.tickSpacing() / 2) _SpacedBase += 1;
        int24 _tickMiddle = _SpacedBase * pool.tickSpacing();
        int24 _tickLower = (_SpacedBase - range) * pool.tickSpacing();
        int24 _tickUpper = (_SpacedBase + range) * pool.tickSpacing();
        // console2.log("_SpacedBase", uint24(_SpacedBase));
        // console2.log(uint24(_currentTick), uint24(_tickMiddle), uint24(_tickLower), uint24(_tickUpper));

        uint256 _amount1Desired = calcAmount1Desired();
        // console2.log("_amount1Desired", _amount1Desired);

        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0Desired);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), _amount1Desired);

        IERC20(token0).safeApprove(address(nonfungiblePositionManager), amount0Desired);
        IERC20(token1).safeApprove(address(nonfungiblePositionManager), _amount1Desired);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: poolFee,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: _amount1Desired,
            amount0Min: amount0Desired * (100 - slippage) / 100,
            amount1Min: _amount1Desired * (100 - slippage) / 100,
            recipient: address(this),
            deadline: block.timestamp
        });
        (_tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);
        tokenId = _tokenId;

        // Remove allowance and refund in both assets.
        if (amount0 < amount0Desired) {
            IERC20(token0).safeApprove(address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0Desired - amount0;
            // console2.log("refund0", refund0);
            IERC20(token0).safeTransfer(msg.sender, refund0);
        }

        if (amount1 < _amount1Desired) {
            IERC20(token1).safeApprove(address(nonfungiblePositionManager), 0);
            uint256 refund1 = _amount1Desired - amount1;
            // console2.log("refund1", refund1);
            IERC20(token1).safeTransfer(msg.sender, refund1);
        }
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collectAllFees() external onlyOwner returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        _sendToOwner(amount0, amount1);
    }

    /// @notice A function that decreases the current liquidity by half. An example to show how to call the `decreaseLiquidity` function defined in periphery.
    /// @return amount0 The amount received back in token0
    /// @return amount1 The amount returned back in token1
    function decreaseLiquidityAll() external onlyOwner returns (uint256 amount0, uint256 amount1) {
        (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
    }

    /// @notice Increases liquidity in the current range
    /// @dev Pool must be initialized already to add liquidity
    /// @param amount0 The amount to add of token0
    /// @param amount1 The amount to add of token1
    function increaseLiquidityCurrentRange(
        uint256 amountAdd0,
        uint256 amountAdd1
    )
        external
        onlyOwner
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amountAdd0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amountAdd1);

        IERC20(token0).safeApprove(address(nonfungiblePositionManager), amountAdd0);
        IERC20(token1).safeApprove(address(nonfungiblePositionManager), amountAdd1);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amountAdd0,
                amount1Desired: amountAdd1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(params);
    }

    function setRange(int24 _range) external onlyOwner{
        range = _range;    
    }

    function setSlippage(uint256 _slippage) external onlyOwner{
        slippage = _slippage;
    }

    function setAmount0Desired(uint256 _amount0Desired) external onlyOwner{
        amount0Desired = _amount0Desired;
    }

    function _newRange() internal returns (int24 _tickLower, int24 _tickUpper) {
        int256 _currentTick = getCurrentTick();
        int24 _tickSpacing = pool.tickSpacing();
        int24 _tickLower = int24(_currentTick) + (_tickSpacing * range);
        int24 _tickUpper = int24(_currentTick) - (_tickSpacing * range);
    }

    function isInRange(uint256 _tokenId) public returns (bool) {
        int256 _currentTick = getCurrentTick();
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = nonfungiblePositionManager.positions(_tokenId);
        return (_currentTick >=tickLower && _currentTick <= tickUpper);
    }

    function getCurrentTick() public returns (int256) {
        (int24 arithmeticMeanTick, ) = pool.consult(1); // 1 second ago

        address[] memory tokens = new address[](2);
        int24[] memory ticks = new int24[](1);
        tokens[0] = token0;
        tokens[1] = token1;
        ticks[0] = arithmeticMeanTick;

        int256 syntheticTick = OracleLibrary.getChainedPrice(tokens, ticks);
        // console2.log(uint(syntheticTick));
        return syntheticTick;
    }

    function calcAmount1Desired() public returns(uint256){
        return OracleLibrary.getQuoteAtTick(
            int24(getCurrentTick()),
            uint128(amount0Desired),
            token0,
            token1
        );
    }

    function isTrasferable() public returns(bool){
        uint256 _amount1Desired = calcAmount1Desired();
        uint256 _token0bal = IERC20(token0).balanceOf(msg.sender);
        uint256 _token1bal = IERC20(token1).balanceOf(msg.sender);
        return (_token0bal >= amount0Desired && _token1bal >= _amount1Desired);
    }

    /// @notice Transfers funds to owner of NFT
    /// @param _amount0 The amount of token0
    /// @param _amount1 The amount of token1
    function _sendToOwner(
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        IERC20(token0).safeTransfer(owner(), _amount0);
        IERC20(token1).safeTransfer(owner(), _amount1);
    }
}

