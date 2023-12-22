// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ====================================================================
// ====================== UniV3Asset.sol ============================
// ====================================================================

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./ISweep.sol";
import "./IERC20Metadata.sol";
import "./Owned.sol";
import "./IERC721Receiver.sol";
import "./TransferHelper.sol";
import "./TickMath.sol";
import "./FixedPoint96.sol";
import "./INonfungiblePositionManager.sol";
import "./ABDKMath64x64.sol";

contract UniV3Asset is IERC721Receiver, Owned {
    // Variables
    uint256 current_value;
    bool public defaulted;
    uint256 public tokenId;
    address public stabilizer;
    address public usdx;
    address public sweep;
    address public token0;
    address public token1;
    uint128 public liquidity;
    uint24 public constant poolFee = 3000; // Fees are 500(0.05%), 3000(0.3%), 10000(1%)
    int24 public constant tickSpacing = 60; // TickSpacings are 10, 60, 200

    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    // Events
    event Mint(uint256 tokenId, uint128 liquidity);
    event Deposit(uint256 amount0, uint256 amount1);
    event Withdraw(uint256 amount0, uint256 amount1);
    event WithdrawRewards(uint256 amount0, uint256 amount1);

    constructor(
        address _owner_address,
        address _stabilizer_address,
        address _usdx_address,
        address _sweep_address,
        INonfungiblePositionManager _nonfungiblePositionManager
    ) Owned(_owner_address) {
        stabilizer = _stabilizer_address;
        usdx = _usdx_address;
        sweep = _sweep_address;
        current_value = 0;
        (token0, token1) = usdx < sweep ? (usdx, sweep) : (sweep, usdx);
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    /* ========== Modifies ========== */

    modifier onlyStabilizer() {
        require(msg.sender == stabilizer, "only stabilizer");
        _;
    }

    /* ========== Views ========== */

    /**
     * @notice Get the ticks which will be used in the creating LP
     * @return minTick The minimum tick
     * @return maxTick The maximum tick
     */
    function showTicks() public view returns (int24 minTick, int24 maxTick) {
        uint256 sweepPrice = ISweep(sweep).target_price();
        uint256 minPrice = (sweepPrice * 99) / 100;
        uint256 maxPrice = (sweepPrice * 101) / 100;

        minTick = getTickFromPrice(minPrice, ISweep(sweep).decimals());
        maxTick = getTickFromPrice(maxPrice, ISweep(sweep).decimals());

        (minTick, maxTick) = minTick < maxTick
            ? (minTick, maxTick)
            : (maxTick, minTick);
    }

    function getTickFromPrice(uint256 _price, uint256 _decimal)
        internal
        view
        returns (int24 _tick)
    {
        int128 value1 = ABDKMath64x64.fromUInt(10**_decimal);
        int128 value2 = ABDKMath64x64.fromUInt(_price);
        int128 value = ABDKMath64x64.div(value2, value1);
        if (token0 != sweep) {
            value = ABDKMath64x64.div(value1, value2);
        }
        _tick = TickMath.getTickAtSqrtRatio(
            uint160(
                int160(
                    ABDKMath64x64.sqrt(value) << (FixedPoint96.RESOLUTION - 64)
                )
            )
        );

        _tick = (_tick / tickSpacing) * tickSpacing;
    }

    /**
     * @notice Gets the current price of AMM
     * @return the current price
     */
    function currentValue() public view returns (uint256) {
        return current_value;
    }

    /**
     * @notice isDefaulted
     * @return bool True: is defaulted, False: not defaulted.
     */
    function isDefaulted() public view returns (bool) {
        return defaulted;
    }

    /* ========== Actions ========== */

    /**
     * @notice setDefaulted
     * @param _defaulted True: is defaulted, False: not defaulted.
     */
    function setDefaulted(bool _defaulted) public onlyOwner {
        defaulted = _defaulted;
    }

    /**
     * @notice Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
     */
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        require(tokenId == 0, "Already minted.");
        _createDeposit(_tokenId);

        return this.onERC721Received.selector;
    }

    function _createDeposit(uint256 _tokenId) internal {
        (
            ,
            ,
            address _token0,
            address _token1,
            ,
            ,
            ,
            uint128 _liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(_tokenId);
        
        require(token0 == _token0 && token1 == _token1, "Invalid Token ID.");
        
        liquidity = _liquidity;
        tokenId = _tokenId;

        emit Mint(_tokenId, _liquidity);
    }

    /**
     * @notice Calls the mint function defined in periphery, mints the same amount of each token.
     * For this example we are providing 1000 USDX and 1000 address(SWEEP) in liquidity
     * @dev Pool must be initialized already to add liquidity
     * @param amount0ToMint Amount of USDX
     * @param amount1ToMint Amount of SWEEP
     * @return _tokenId The id of the newly minted ERC721
     * @return _liquidity The amount of liquidity for the position
     * @return _amount0 The amount of token0
     * @return _amount1 The amount of token1
     */
    function mint(uint256 amount0ToMint, uint256 amount1ToMint)
        internal
        returns (
            uint256 _tokenId,
            uint128 _liquidity,
            uint256 _amount0,
            uint256 _amount1
        )
    {
        (int24 minTick, int24 maxTick) = showTicks();

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: poolFee,
                tickLower: minTick,
                tickUpper: maxTick,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        // Note that the pool defined by token0/token1 and fee tier 0.3% must already be created and initialized in order to mint
        (_tokenId, _liquidity, _amount0, _amount1) = nonfungiblePositionManager.mint(params);

        // Create a deposit
        _createDeposit(_tokenId);
    }

    /**
     * @notice Increases liquidity in the current range
     * @dev Pool must be initialized already to add liquidity
     * @param _usdx_amount USDX Amount of asset to be deposited
     * @param _sweep_amount Sweep Amount of asset to be deposited
     */
    function deposit(uint256 _usdx_amount, uint256 _sweep_amount)
        external
        onlyStabilizer
    {
        require(_usdx_amount > 0 && _sweep_amount > 0, "Should be over zero.");
        
        TransferHelper.safeTransferFrom(
            usdx,
            msg.sender,
            address(this),
            _usdx_amount
        );
        TransferHelper.safeTransferFrom(
            sweep,
            msg.sender,
            address(this),
            _sweep_amount
        );
        TransferHelper.safeApprove(
            usdx,
            address(nonfungiblePositionManager),
            _usdx_amount
        );
        TransferHelper.safeApprove(
            sweep,
            address(nonfungiblePositionManager),
            _sweep_amount
        );

        uint128 _liquidity;
        uint256 _amount0;
        uint256 _amount1;
        (uint256 amountAdd0, uint256 amountAdd1) = usdx < sweep
            ? (_usdx_amount, _sweep_amount)
            : (_sweep_amount, _usdx_amount);

        if (tokenId == 0) {
            (, _liquidity, _amount0, _amount1) = mint(amountAdd0, amountAdd1);
        } else {
            (_liquidity, _amount0, _amount1) = nonfungiblePositionManager
                .increaseLiquidity(
                    INonfungiblePositionManager.IncreaseLiquidityParams({
                        tokenId: tokenId,
                        amount0Desired: amountAdd0,
                        amount1Desired: amountAdd1,
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: block.timestamp + 60 // Expiration: 1 hour from now
                    })
                );
            liquidity += _liquidity;
        }

        // Remove allowance and refund in both assets.
        if (_amount0 < amountAdd0) {
            TransferHelper.safeApprove(
                token0,
                address(nonfungiblePositionManager),
                0
            );
            uint256 refund0 = amountAdd0 - _amount0;
            TransferHelper.safeTransfer(token0, msg.sender, refund0);
        }

        if (_amount1 < amountAdd1) {
            TransferHelper.safeApprove(
                token1,
                address(nonfungiblePositionManager),
                0
            );
            uint256 refund1 = amountAdd1 - _amount1;
            TransferHelper.safeTransfer(token1, msg.sender, refund1);
        }

        (uint256 deposited_usdx, uint256 deposited_sweep) = usdx < sweep ? (_amount0, _amount1) : (_amount1, _amount0);
        uint256 sweep_in_usdx = SWEEPinUSDX(deposited_sweep, ISweep(sweep).target_price());
        current_value += deposited_usdx;
        current_value += sweep_in_usdx;

        emit Deposit(_amount0, _amount1);
    }

    /**
     * @notice A function that decreases the current liquidity.
     * @param _amount Liquidity Amount to decrease
     */
    function withdraw(uint256 _amount) external onlyStabilizer {
        require(tokenId > 0, "Should mint first.");
        uint128 decreaseLP = uint128(_amount);
        require(decreaseLP <= liquidity, "Should be less than liquidity");
        liquidity -= decreaseLP;

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: decreaseLP,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        nonfungiblePositionManager.decreaseLiquidity(params);

        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.collect(
            INonfungiblePositionManager.CollectParams(
                tokenId,
                msg.sender,
                type(uint128).max,
                type(uint128).max
            )
        );

        emit Withdraw(amount0, amount1);
    }

    /**
     * @notice Collects the fees associated with provided liquidity
     * @dev The contract must hold the erc721 token before it can collect fees
     * @param _to Address
     */
    function withdrawRewards(address _to) external onlyStabilizer {
        require(tokenId > 0, "Should mint first.");
        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: _to,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.collect(
            params
        );

        emit WithdrawRewards(amount0, amount1);
    }

    /**
     * @notice Function to Recover Erc20 token to Stablizer
     * @param _token token address to be recovered
     * @param _amount token amount to be recovered
     */
    function recoverERC20(address _token, uint256 _amount)
        external
        onlyStabilizer
    {
        TransferHelper.safeTransfer(address(_token), msg.sender, _amount);
    }

    /**
     * @notice Transfers the NFT to the owner
     */
    function retrieveNFT() external onlyOwner {
        require(tokenId > 0, "Should mint first.");
        // transfer ownership to original owner
        nonfungiblePositionManager.safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );

        tokenId = 0;
    }

    /**
     * @notice SWEEP in USDX
     * Calculate the amount of USDX that are equivalent to the SWEEP input.
     * @param amount Amount of SWEEP.
     * @param price Price of Sweep in USDX. This value is obtained from the AMM.
     * @return amount of USDX.
     * @dev 1e6 = PRICE_PRECISION
     */
    function SWEEPinUSDX(uint256 amount, uint256 price)
        internal
        view
        returns (uint256)
    {
        return (amount * price * (10**IERC20Metadata(usdx).decimals())) / (10**ISweep(sweep).decimals() * 1e6);
    }

    function updateValue(uint256) external pure {}
}

