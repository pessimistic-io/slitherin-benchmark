// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./INonfungiblePositionManager.sol";
import "./SafeERC20.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./IQuoter.sol";
import "./IWETH9.sol";
import "./TickMath.sol";

import "./console.sol";
import "./ISwapRouter.sol";
import "./LiquidityAmounts.sol";


contract RangePositionManager {
    using SafeERC20 for IERC20;

    uint256 public currentTokenId;
    uint128 public totalLiquidity;

    int24 internal currentTickLower;
    int24 internal currentTickUpper;

    address internal WETH;
    address internal token0;
    address internal token1;
    uint24 internal fee;

    int24 public tickMovement; // 1 tick = 0.01% in price movement (1 basis point = 0.01%, 50 basis points = 0.5%, 100 basis points = 1%)
    int24 public tickMoveThreshold; // Maximum acceptable price deviation threshold in basis points (1 basis point = 0.01%, 50 basis points = 0.5%, 100 basis points = 1%)

    // indicates if the mint and increase liquidity is locked
    bool public isLocked;

    address internal yieldManager;
    address public owner;
    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool internal uniswapV3Pool;
    IUniswapV3Factory internal uniswapV3Factory;
    ISwapRouter internal uniswapV3Router;
    IQuoter internal uniswapQuoter;

    address[] public userList;

    // structs
    struct UserInfo {
        uint liquidity;
        uint earnTimestamp;
        uint token0Balance;
        uint token1Balance;
    }

    // struct for handling the variable sin moveRange
    struct MoveRangeParams {
        uint160 sqrtPriceX96;
        uint decreaseAmount0;
        uint decreaseAmount1;
        uint amount0;
        uint amount1;
        int24 currentTick;
        int24 tickSpace;
        int24 currentTickUpperInterpolated;
        int24 newTickUpper;
        int24 newTickLower;
        uint160 sqrtPriceLimitX96;
        uint160 sqrtRatioA;
        uint160 sqrtRatioB;
        address tokenIn;
        address tokenOut;
        uint amountIn;
        uint amountOutQuote;
        uint amountOutMinimum;
    }

    // mappings
    mapping(address => UserInfo) public userMapping;
    mapping(address => bool) internal isUser; // default `false`

    // only owner modifier
    modifier onlyOwner {
        _onlyOwner();
        _;
    }

    // only owner view
    function _onlyOwner() private view {
        require(msg.sender == owner || msg.sender == address(this), "Only the contract owner may perform this action");
    }

    event Mint(uint amount0, uint amount1, uint liquidity, uint tokenId, address user);
    event IncreaseLiquidity(uint amount0, uint amount1, uint liquidity, address user);
    event RemovedLiquidity(uint amount0, uint amount1, uint liquidity, address user);
    event FeesWithdrawn(uint amount0, uint amount1, address user);
    event NewTickMovement(int24 tickMovement);
    event NewSponsor(address sponsor, address client);
    event NewYieldManager(address yieldManager);
    event NewOwner(address owner);
    event Locked(bool locked);
    event MovedRange(int24 tickLower, int24 tickUpper);
    event NewTickMoveThreshold(int24 tickMove);

    constructor(
        address _owner,
        address _positionManager,
        address _uniswapV3Router,
        address _uniswapQuoter,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickMovement,
        int24 _tickMoveThreshold,
        address _yieldManager
    ){
        owner = _owner;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;

        positionManager = INonfungiblePositionManager(_positionManager);
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        uniswapQuoter = IQuoter(_uniswapQuoter);
        uniswapV3Factory = IUniswapV3Factory(positionManager.factory());
        uniswapV3Pool = IUniswapV3Pool(uniswapV3Factory.getPool(token0, token1, fee));
        WETH = positionManager.WETH9();

        tickMovement = _tickMovement;
        tickMoveThreshold = _tickMoveThreshold;
        yieldManager = _yieldManager;
    }

    /// Function for the first mint of the initial position nft
    /// @dev mints the first initial position NFT, can only be called by the owner
    /// @param tickLower the lower tick
    /// @param tickUpper the upper tick
    /// @param amountDesired0 the amount of token0 desired
    /// @param amountDesired1 the amount of token1 desired
    /// @param slippagePercent slippage amount for protection
    function mintOwner(
        int24 tickLower,
        int24 tickUpper,
        uint amountDesired0,
        uint amountDesired1,
        uint slippagePercent
    )
    external payable onlyOwner {
        require(totalLiquidity == 0);
        mint(tickLower, tickUpper, amountDesired0, amountDesired1, slippagePercent, false);
    }

    /// Internal mint function
    /// @dev mints position NFTs according to the params. Can be a first time mint from the owner, or moveRange mint
    /// @param tickLower the lower tick
    /// @param tickUpper the upper tick
    /// @param amountDesired0 the amount of token0 desired
    /// @param amountDesired1 the amount of token1 desired
    /// @param slippagePercent slippage amount for protection
    /// @param contractCall indicated if it is a moveRange call (coming from the contract itself)
    function mint(
        int24 tickLower,
        int24 tickUpper,
        uint amountDesired0,
        uint amountDesired1,
        uint slippagePercent,
        bool contractCall
    ) internal {
        // check if locked
        require(!isLocked, "Locked for minting");

        // get mint decreaseParams
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams(
            {
                token0 : token0,
                token1 : token1,
                fee : fee,
                tickLower : tickLower,
                tickUpper : tickUpper,
                amount0Desired : amountDesired0,
                amount1Desired : amountDesired1,
                amount0Min : amountDesired0 - (amountDesired0 * slippagePercent / 10000),
                amount1Min : amountDesired1 - (amountDesired1 * slippagePercent / 10000),
                recipient : address(this),
                deadline : block.timestamp
            }
        );

        // handle the approvals for ERC20 tokens
        if (mintParams.token0 != WETH) {
            IERC20(mintParams.token0).safeApprove(address(positionManager), 0);
            IERC20(mintParams.token0).safeApprove(address(positionManager), mintParams.amount0Desired);
        }

        if (mintParams.token1 != WETH) {
            IERC20(mintParams.token1).safeApprove(address(positionManager), 0);
            IERC20(mintParams.token1).safeApprove(address(positionManager), mintParams.amount1Desired);
        }

        // define output variables for later usage
        uint256 tokenId;
        uint256 amount0;
        uint256 amount1;
        uint128 liquidity;

        // call this if it is a reposition call
        if (contractCall) {
            (tokenId, liquidity, amount0, amount1) = positionManager.mint{value : token0 == WETH ? mintParams.amount0Desired : (token1 == WETH ? mintParams.amount1Desired : 0)}(mintParams);
            positionManager.refundETH();

            console.log("mint amounts after");
            console.log("0: %s", amount0);
            console.log("1: %s", amount1);

            uint amount0Diff = amountDesired0 - amount0;
            uint amount1Diff = amountDesired1 - amount1;

            // update user percentages
            for (uint i = 0; i < userList.length; i++) {
                UserInfo storage userElement = userMapping[userList[i]];
                userElement.liquidity = userElement.liquidity * liquidity / totalLiquidity;

                if (amountDesired0 > 0) {
                    userElement.token0Balance += amount0Diff * userElement.liquidity / liquidity;
                }
                if (amountDesired1 > 0) {
                    userElement.token1Balance += amount1Diff * userElement.liquidity / liquidity;
                }
            }
        }

        // sender is not the contract, first owner call
        else {
            (tokenId, liquidity, amount0, amount1) = positionManager.mint{value : msg.value}(mintParams);
            // housekeeping for first mint
            positionManager.refundETH();
            // sweep the remaining tokens
            if (token0 != WETH) {
                positionManager.sweepToken(token0, 0, address(this));
            }
            if (token1 != WETH) {
                positionManager.sweepToken(token1, 0, address(this));
            }

            console.log("mint test");
            console.log("amount1: %s", amount1);
            console.log("amountDesired1: %s", amountDesired1);
            console.log("amount0: %s", amount0);
            console.log("amountDesired0: %s", amountDesired0);

            // refunds
            if (token0 == WETH && (address(this).balance > 0)) {
                payable(msg.sender).transfer(address(this).balance);
            }
            if (token1 == WETH && (address(this).balance > 0)) {
                payable(msg.sender).transfer(address(this).balance);
            }
            if (token0 != WETH && IERC20(token0).balanceOf(address(this)) > 0) {
                IERC20(token0).safeTransfer(msg.sender, IERC20(token0).balanceOf(address(this)));
            }
            if (token1 != WETH && IERC20(token1).balanceOf(address(this)) > 0) {
                IERC20(token1).safeTransfer(msg.sender, IERC20(token1).balanceOf(address(this)));
            }

            //add owner init as user used for owner decrease after potential lock
            if (isUser[msg.sender] == false) {
                // update user mapping
                UserInfo storage userElement = userMapping[msg.sender];
                userElement.liquidity += liquidity;

                // push the unique item to the array
                userList.push(msg.sender);
                isUser[msg.sender] = true;
            }
        }

        totalLiquidity = liquidity;
        currentTokenId = tokenId;
        currentTickUpper = tickUpper;
        currentTickLower = tickLower;

        emit Mint(amount0, amount1, liquidity, currentTokenId, msg.sender);
    }

    /// Checks if range can be moved
    /// @dev checks if the range position can be moved
    /// returns a bool indicating if position can be moved or not
    function canMoveRange() public view returns (bool) {
        // get the current tick
        (,int24 currentTick,,,,,) = uniswapV3Pool.slot0();

        // delta can never be a negative number
        int256 delta = int256(currentTickUpper) - int256(currentTickLower);
        int256 hardLimitTickUpper = int256(currentTickUpper) - (tickMoveThreshold * delta / 10000);
        int256 hardLimitTickLower = int256(currentTickLower) + (tickMoveThreshold * delta / 10000);

        return currentTick > hardLimitTickUpper || currentTick < hardLimitTickLower;
    }

    /// function for moving range
    /// @dev this function is used to move the liquidity ranges (lower tick, upper tick). If possible (within the threshold)
    /// @dev it is possible to call this function. It will decrease all liquidity from the position, swap tokens in a 50:50 ratio
    /// @dev and then mint a new position using this tokens swapped. Users will get the share of the new liquidity pro rata
    /// @param slippagePercent the slippage setting
    function moveRange
    (
        uint slippagePercent
    )
    external
    {
        require(currentTokenId != 0, 'Not initialized');
        //require(canMoveRange(), "Not allowed to move range");

        // collect fees
        collect(0, 0);

        MoveRangeParams memory params;

        // calculate the amount of token0 and token1 based on the percentage of liquidity to be removed
        (params.sqrtPriceX96,,,,,,) = uniswapV3Pool.slot0();

        params.sqrtRatioA = TickMath.getSqrtRatioAtTick(currentTickLower);
        params.sqrtRatioB = TickMath.getSqrtRatioAtTick(currentTickUpper);
        (params.decreaseAmount0, params.decreaseAmount1) = LiquidityAmounts.getAmountsForLiquidity(params.sqrtPriceX96, params.sqrtRatioA, params.sqrtRatioB, totalLiquidity);

        console.log("amount0wei LIB  : %s", params.decreaseAmount0);
        console.log("amount1wei LIB  : %s", params.decreaseAmount1);

        // decrease to 0
        (params.amount0, params.amount1) = decreaseLiquidity(params.decreaseAmount0, params.decreaseAmount1, slippagePercent, totalLiquidity, address(this), true);

        // burn the position
        positionManager.burn(currentTokenId);

        // mint new
        (,params.currentTick,,,,,) = uniswapV3Pool.slot0();
        params.tickSpace = uniswapV3Pool.tickSpacing();

        //get tick interpolated to the nearest tick space
        params.currentTickUpperInterpolated = int24(params.currentTick / params.tickSpace) * params.tickSpace;

        // each tick being a .01% (1 basis point) price movement away from each of its neighboring ticks. to increase rang of eg 50% add 5000. for 0.01% add 1
        params.newTickLower = params.currentTickUpperInterpolated - params.tickSpace * tickMovement;
        params.newTickUpper = params.currentTickUpperInterpolated + params.tickSpace * tickMovement;

        //calculate how much we need to swap to fulfill the required amounts
        uint swapAmount0 = params.amount0 > params.amount1 ? params.amount0 : 0;
        uint swapAmount1 = params.amount1 > params.amount0 ? params.amount1 : 0;

        console.log("amount0  : %s", params.amount0);
        console.log("amount1  : %s", params.amount1);

        console.log("swapAmount0  : %s", swapAmount0);
        console.log("swapAmount1  : %s", swapAmount1);
        console.log("!!!!!!!!!!!!!");


        console.log("swapAmount0  : %s", params.sqrtPriceLimitX96);
        console.log("swapAmount1  : %s", TickMath.getSqrtRatioAtTick(params.newTickLower));

        params.tokenIn = (swapAmount0 > 0) ? token0 : token1; // Token to swap from (0 if amount0 should be increased, 1 if amount1 should be increased)
        params.tokenOut = (swapAmount0 > 0) ? token1 : token0; // Token to receive (opposite of tokenIn)
        params.amountIn = (swapAmount0 > 0) ? swapAmount0 : swapAmount1; // Amount to swap from (either swapAmount0 or swapAmount1)

        bool zeroForOne = params.tokenIn < params.tokenOut;
        params.amountOutQuote = uniswapQuoter.quoteExactInputSingle(params.tokenIn, params.tokenOut, fee, params.amountIn, params.sqrtPriceLimitX96);
        params.amountOutMinimum = params.amountOutQuote - (params.amountOutQuote * slippagePercent / 10000);

        // we swap all 0 or 1 into 1 token
        // Perform the token swap using Uniswap V3 SwapRouter (example code, comment only)
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: params.amountIn,
            amountOutMinimum: params.amountOutMinimum,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        // Perform the token approval for the swap
        if (swapParams.tokenIn != WETH) {
            IERC20(swapParams.tokenIn).safeApprove(address(uniswapV3Router), 0);
            IERC20(swapParams.tokenIn).safeApprove(address(uniswapV3Router), swapParams.amountIn);
        }

        // The call to `exactInputSingle` executes the swap.
        uint returnFromSwap = uniswapV3Router.exactInputSingle{value: swapParams.tokenIn == WETH ? swapParams.amountIn : 0}(swapParams);
        console.log("return %s", returnFromSwap);

        if (swapParams.tokenOut == WETH) {
            IWETH9(WETH).approve(WETH, 0);
            IWETH9(WETH).approve(WETH, IERC20(WETH).balanceOf(address(this)));
            IWETH9(WETH).withdraw(IERC20(WETH).balanceOf(address(this)));
        }

        zeroForOne = swapParams.tokenOut < swapParams.tokenIn;
        params.amountOutQuote = uniswapQuoter.quoteExactInputSingle(swapParams.tokenOut, swapParams.tokenIn, fee, returnFromSwap / 2, params.sqrtPriceLimitX96);
        params.amountOutMinimum = params.amountOutQuote - (params.amountOutQuote * slippagePercent / 10000);

        // after this we have all in one token
        // we swap all 0 or 1 into 1 token
        // Perform the token swap using Uniswap V3 SwapRouter (example code, comment only)
        ISwapRouter.ExactInputSingleParams memory swapParamsNew = ISwapRouter.ExactInputSingleParams({
            tokenIn: swapParams.tokenOut,  // Token to swap from (0 if amount0 should be increased, 1 if amount1 should be increased)
            tokenOut: swapParams.tokenIn, // Token to receive (opposite of tokenIn)
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: returnFromSwap / 2, // Amount to swap from (either swapAmount0 or swapAmount1)
            amountOutMinimum: params.amountOutMinimum,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        // Perform the token approval for the swap
        if (swapParamsNew.tokenIn != WETH) {
            IERC20(swapParamsNew.tokenIn).safeApprove(address(uniswapV3Router), 0);
            IERC20(swapParamsNew.tokenIn).safeApprove(address(uniswapV3Router), swapParamsNew.amountIn);
            console.log("we have WETH");
        }
        console.log("we have WETH1");
        console.log("we have token1: %s", swapParamsNew.tokenIn);

        // get eth back
        if (swapParamsNew.tokenOut == WETH) {
            IWETH9(WETH).approve(WETH, 0);
            IWETH9(WETH).approve(WETH, IERC20(WETH).balanceOf(address(this)));
            IWETH9(WETH).withdraw(IERC20(WETH).balanceOf(address(this)));
        }

        // The call to `exactInputSingle` executes the swap.
        uint returnFromSwapFinal = uniswapV3Router.exactInputSingle{value: swapParamsNew.tokenIn == WETH ? swapParamsNew.amountIn : 0}(swapParamsNew);

        console.log("mint amounts");
        console.log("0: %s", returnFromSwap/2);

        // mint new position
        mint(params.newTickLower, params.newTickUpper, returnFromSwap/2, returnFromSwapFinal, slippagePercent, true);
        emit MovedRange(params.newTickLower, params.newTickUpper);
    }

    /// function for increasing liquidity
    /// @dev for increasing liquidity, also sets the sponsor if new user
    /// @param amountDesired0 the minimum amount to use of token0
    /// @param amountDesired1 the minimum amount to use of token1
    /// @param slippagePercent the slippage setting
    /// @param sponsor the address of the sponsor
    function increaseLiquidity(
        uint amountDesired0,
        uint amountDesired1,
        uint slippagePercent,
        address sponsor
    )
    external
    payable
    {
        // check if locked
        require(!isLocked, "Locked for increasing liquidity");

        // set new sponsor if needed
        if (sponsor != address(0) && sponsor != msg.sender && IYieldManager(yieldManager).getAffiliate(msg.sender) == address(0)) {
            IYieldManager(yieldManager).setAffiliate(msg.sender, sponsor);
            emit NewSponsor(sponsor, msg.sender);
        }

        // get increase params
        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseParams = INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId : currentTokenId,
            amount0Desired : amountDesired0,
            amount1Desired : amountDesired1,
            amount0Min : amountDesired0 - (amountDesired0 * slippagePercent / 10000),
            amount1Min : amountDesired1 - (amountDesired1 * slippagePercent / 10000),
            deadline : block.timestamp
        });

        // handle approvals
        if (token0 != WETH) {
            IERC20(token0).safeTransferFrom(msg.sender, address(this), amountDesired0);
            IERC20(token0).safeApprove(address(positionManager), 0);
            IERC20(token0).safeApprove(address(positionManager), amountDesired0);
        }

        if (token1 != WETH) {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amountDesired1);
            IERC20(token1).safeApprove(address(positionManager), 0);
            IERC20(token1).safeApprove(address(positionManager), amountDesired1);
        }

        (uint128 liquidity, uint256 amount0, uint256 amount1) = positionManager.increaseLiquidity{value : msg.value}(increaseParams);
        positionManager.refundETH();

        console.log("increase check");
        console.log("increase 0 : %s", amount0);
        console.log("increase 1 : %s", amount1);

        // update user mapping
        UserInfo storage userElement = userMapping[msg.sender];
        userElement.liquidity += liquidity;
        userElement.earnTimestamp = block.timestamp + 60 * 60 * 24;

        // check against the mapping
        if (isUser[msg.sender] == false) {
            // push the unique item to the array
            userList.push(msg.sender);
            isUser[msg.sender] = true;
        }

        // send back tokens
        if (token0 == WETH && (msg.value - amount0 > 0)) {
            payable(msg.sender).transfer(msg.value - amount0);
        }
        if (token1 == WETH && (msg.value - amount1 > 0)) {
            payable(msg.sender).transfer(msg.value - amount1);
        }
        if (token0 != WETH && amountDesired0 - amount0 > 0) {
            IERC20(token0).safeTransfer(msg.sender, amountDesired0 - amount0);
        }
        if (token1 != WETH && amountDesired1 - amount1 > 0) {
            IERC20(token1).safeTransfer(msg.sender, amountDesired1 - amount1);
        }

        totalLiquidity += liquidity;
        emit IncreaseLiquidity(amount0, amount1, liquidity, msg.sender);
    }


    /// function for decreasing liquidity, for msg.sender
    /// @dev for decreasing liquidity, for msg.sender
    /// @param amount0Min the minimum amount to receive of token0
    /// @param amount1Min the minimum amount to receive of token1
    /// @param slippagePercent the slippage setting
    /// @param liquidity the amount of liquidity to be decreased
    function decreaseLiquidityUser(
        uint amount0Min,
        uint amount1Min,
        uint slippagePercent,
        uint128 liquidity
    )
    external
    {
        //get user element
        UserInfo storage userElement = userMapping[msg.sender];

        // check for liquidity
        require(liquidity <= userElement.liquidity);

        // perform decrease liquidity
        decreaseLiquidity(amount0Min, amount1Min, slippagePercent, liquidity, msg.sender, false);
    }

    /// function for decreasing liquidity, used by governance to force decrease of a specific user after x amount of time
    /// @dev for decreasing liquidity, used by governance to force decrease of a specific user after x amount of time
    /// @param amount0Min the minimum amount to receive of token0
    /// @param amount1Min the minimum amount to receive of token1
    /// @param slippagePercent the slippage setting
    /// @param liquidity the amount of liquidity to be decreased
    /// @param userToDecrease the user address to be decreased
    function decreaseLiquidityUserForce(
        uint amount0Min,
        uint amount1Min,
        uint slippagePercent,
        uint128 liquidity,
        address userToDecrease
    )
    external
    onlyOwner
    {
        //get user element
        UserInfo storage userElement = userMapping[userToDecrease];

        // check for liquidity
        require(liquidity <= userElement.liquidity);

        // perform decrease liquidity
        decreaseLiquidity(amount0Min, amount1Min, slippagePercent, liquidity, userToDecrease, false);
    }

    /// function for decreasing liquidity, internal, can be used for user decrease, forced decrease or internal new mint decrease
    /// @dev for decreasing liquidity, internal, can be used for user decrease, forced decrease or internal new mint decrease
    /// @param amount0Min the minimum amount to receive of token0
    /// @param amount1Min the minimum amount to receive of token1
    /// @param slippagePercent the slippage setting
    /// @param liquidity the amount of liquidity to be decreased
    /// @param userToDecrease the user address to be decreased
    /// @param contractCall indicated if call comes from inside the contract or user action
    /// @return amount0 the amount how much token0 we got as return
    /// @return amount1 the amount how much token1 we got as return
    function decreaseLiquidity(
        uint amount0Min,
        uint amount1Min,
        uint slippagePercent,
        uint128 liquidity,
        address userToDecrease,
        bool contractCall
    )
    internal
    returns
    (
        uint amount0,
        uint amount1
    )
    {
        // build decrease params
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId : currentTokenId,
            liquidity : liquidity,
            amount0Min : amount0Min - (amount0Min * slippagePercent / 10000),
            amount1Min : amount1Min - (amount1Min * slippagePercent / 10000),
            deadline : block.timestamp
        });

        console.log("decreease");
        console.log("liquidity: %s", liquidity);

        uint balanceBefore = address(this).balance;
        console.log("balanceBefore: %s", balanceBefore);

        (amount0, amount1) = positionManager.decreaseLiquidity(decreaseParams);

        collect(amount0, amount1);

        if (!contractCall) {
            //get user element
            UserInfo storage userElement = userMapping[userToDecrease];
            // housekeeping
            userElement.liquidity -= liquidity;

            // if no liquidity we remove user
            if (userElement.liquidity == 0) {
                for (uint i = 0; i < userList.length; i++) {
                    if (userList[i] == userToDecrease) {
                        delete userList[i];
                        break;
                    }
                }
                isUser[userToDecrease] = false;
            }

            totalLiquidity -= liquidity;

            // fees
            // get user stats
            (, , uint val3,) = IYieldManager(yieldManager).getUserFactors(
                userToDecrease,
                0
            );

            uint mgmtFee0 = (val3 * amount0) / 100 / 100;
            uint sponsorFee0;
            uint mgmtFee1 = (val3 * amount1) / 100 / 100;
            uint sponsorFee1;

            // get sponsor
            address sponsor = IYieldManager(yieldManager).getAffiliate(userToDecrease);
            // get sponsor stats
            if (sponsor != address(0)) {
                (, uint sval2,,) = IYieldManager(yieldManager)
                .getUserFactors(sponsor, 1);
                sponsorFee0 = (mgmtFee0 * sval2) / 100 / 100;
                mgmtFee0 -= sponsorFee0;
                sponsorFee1 = (mgmtFee1 * sval2) / 100 / 100;
                mgmtFee1 -= sponsorFee1;
            }
            // update user mapping
            UserInfo storage userElementOwner = userMapping[owner];

            // send back tokens
            if (token0 == WETH && (amount0 - mgmtFee0 - sponsorFee0 > 0)) {
                payable(userToDecrease).transfer(amount0 - mgmtFee0 - sponsorFee0);
                userElementOwner.token0Balance += mgmtFee0;

                if (sponsor != address(0) && sponsorFee0 != 0) {
                    payable(sponsor).transfer(sponsorFee0);
                }
            }
            if (token1 == WETH && (amount1 - mgmtFee1 - sponsorFee1 > 0)) {
                payable(userToDecrease).transfer(amount1 - mgmtFee1 - sponsorFee1);
                userElementOwner.token1Balance += mgmtFee1;

                if (sponsor != address(0) && sponsorFee1 != 0) {
                    payable(sponsor).transfer(sponsorFee1);
                }
            }
            if (token0 != WETH && amount0 - mgmtFee0 - sponsorFee0 > 0) {
                IERC20(token0).safeTransfer(userToDecrease, amount0 - mgmtFee0 - sponsorFee0);
                userElementOwner.token0Balance += mgmtFee0;

                if (sponsor != address(0) && sponsorFee0 != 0) {
                    IERC20(token0).transfer(sponsor, sponsorFee0);
                }
            }
            if (token1 != WETH && amount1 - mgmtFee1 - sponsorFee1 > 0) {
                IERC20(token1).safeTransfer(userToDecrease, amount1 - mgmtFee1 - sponsorFee1);
                userElementOwner.token1Balance += mgmtFee1;
                if (sponsor != address(0) && sponsorFee1 != 0) {
                    IERC20(token0).transfer(sponsor, sponsorFee1);
                }
            }
        }

        emit RemovedLiquidity(amount0, amount1, liquidity, userToDecrease);
    }

    /// function for handling the collect
    /// @dev collects from a public address, can be called by anyone - used to collect fees
    /// @return amount0 the amount how much token0 we got as fees
    /// @return amount1 the amount how much token1 we got as fees
    function publicCollect() external returns
    (
        uint256 amount0,
        uint256 amount1
    )
    {
        (amount0, amount1) = collect(0, 0);
    }

    /// function for handling the collect from the position manager contract
    /// @dev collects the accrued fees from the position manager contract and withdraws them to this contract
    /// @param decrease0 the amount how much token0 are currently in the contract after a decrease
    /// @param decrease0 the amount how much token1 are currently in the contract after a decrease
    /// @return amount0 the amount how much token0 we got as fees
    /// @return amount1 the amount how much token1 we got as fees
    function collect(uint decrease0, uint decrease1) internal returns
    (
        uint256 amount0,
        uint256 amount1
    )
    {
        // prepare collect params
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams(
            {
                tokenId : currentTokenId,
                recipient : address(this),
                amount0Max : type(uint128).max,
                amount1Max : type(uint128).max
            }
        );

        (amount0, amount1) = positionManager.collect(collectParams);

        // we need to account the tokens and then account fees
        amount0 -= decrease0;
        amount1 -= decrease1;

        positionManager.unwrapWETH9(0, address(this));

        console.log("decrease0: %s", decrease0);
        console.log("decrease1: %s", decrease1);
        console.log("amount0c: %s", amount0);
        console.log("amount1c: %s", amount1);

        // convert weth9
        IWETH9(WETH).approve(WETH, 0);
        IWETH9(WETH).approve(WETH, IERC20(WETH).balanceOf(address(this)));
        IWETH9(WETH).withdraw(IERC20(WETH).balanceOf(address(this)));

        // sweep the remaining tokens
        if (token0 != WETH) {
            positionManager.sweepToken(token0, 0, address(this));
        }
        if (token1 != WETH) {
            positionManager.sweepToken(token1, 0, address(this));
        }

        // check for every user and allocate fee rewards
        for (uint i = 0; i < userList.length; i++) {
            UserInfo storage userElement = userMapping[userList[i]];

            // only if grace period is over we account
            if (userElement.earnTimestamp <= block.timestamp) {
                uint share0 = amount0 * userElement.liquidity / totalLiquidity;
                uint share1 = amount1 * userElement.liquidity / totalLiquidity;

                console.log("%s", msg.sender);
                console.log("share0: %s", share0);
                console.log("share1: %s", share1);

                userElement.token0Balance += share0;
                userElement.token1Balance += share1;
            }
        }
    }

    /// function to collect the accrued fees
    /// @dev used to collect the earned fees from the contract (as a user)
    function userCollect() external {
        // get user
        UserInfo storage userElement = userMapping[msg.sender];
        uint token0Balance = userElement.token0Balance;
        uint token1Balance = userElement.token1Balance;

        // check if no owner
        if (msg.sender != owner) {
            (, uint val2,,) = IYieldManager(yieldManager).getUserFactors(
                msg.sender,
                0
            );

            uint perfFee0 = (val2 * token0Balance) / 100 / 100;
            uint sPerfFee0;

            uint perfFee1 = (val2 * token1Balance) / 100 / 100;
            uint sPerfFee1;

            // sponsor lookup
            address sponsor = IYieldManager(yieldManager).getAffiliate(msg.sender);

            // get sponsor stats
            if (sponsor != address(0)) {
                (uint sval1,,,) = IYieldManager(yieldManager)
                .getUserFactors(sponsor, 1);
                sPerfFee0 = (perfFee0 * sval1) / 100 / 100;
                perfFee0 -= sPerfFee0;
                sPerfFee1 = (perfFee1 * sval1) / 100 / 100;
                perfFee1 -= sPerfFee1;
            }

            // update user mapping
            UserInfo storage ownerElement = userMapping[owner];

            // send tokens
            if (token0 == WETH && (token0Balance - perfFee0 - sPerfFee0 > 0)) {
                console.log("check contract");
                console.log("address(this).balance: %s", address(this).balance);
                console.log("token0Balance: %s", token0Balance);
                payable(msg.sender).transfer(token0Balance - perfFee0 - sPerfFee0);
                ownerElement.token0Balance += perfFee0;

                if (sponsor != address(0) && sPerfFee0 != 0) {
                    payable(sponsor).transfer(sPerfFee0);
                }
            }
            if (token1 == WETH && (token1Balance - perfFee1 - sPerfFee1 > 0)) {
                payable(msg.sender).transfer(token1Balance - perfFee1 - sPerfFee1);
                ownerElement.token1Balance += perfFee1;

                if (sponsor != address(0) && sPerfFee1 != 0) {
                    payable(sponsor).transfer(sPerfFee1);
                }
            }
            if (token0 != WETH && token0Balance - perfFee0 - sPerfFee0 > 0) {
                IERC20(token0).safeTransfer(msg.sender, token0Balance - perfFee0 - sPerfFee0);
                ownerElement.token0Balance += perfFee0;

                if (sponsor != address(0) && sPerfFee0 != 0) {
                    IERC20(token0).transfer(sponsor, sPerfFee0);
                }
            }
            if (token1 != WETH && token1Balance - perfFee1 - sPerfFee1 > 0) {
                IERC20(token1).safeTransfer(msg.sender, token1Balance - perfFee1 - sPerfFee1);
                ownerElement.token1Balance += perfFee1;

                if (sponsor != address(0) && sPerfFee1 != 0) {
                    IERC20(token1).transfer(sponsor, sPerfFee1);
                }
            }
        }
        // user is owner
        else {
            // send tokens
            if (token0 == WETH && (token0Balance > 0)) {
                payable(msg.sender).transfer(token0Balance);
            }
            if (token1 == WETH && (token1Balance > 0)) {
                payable(msg.sender).transfer(token1Balance);
            }
            if (token0 != WETH && token0Balance > 0) {
                IERC20(token0).safeTransfer(msg.sender, token0Balance);

            }
            if (token1 != WETH && token1Balance > 0) {
                IERC20(token1).safeTransfer(msg.sender, token1Balance);
            }
        }

        // set fees to 0 since withdrawn
        userElement.token0Balance = 0;
        userElement.token1Balance = 0;

        emit FeesWithdrawn(token0Balance, token1Balance, msg.sender);
    }

    /// sets the new owner
    /// @dev sets the value of the owner
    /// @param _newOwner the new value for _newOwner
    function changeOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;
        emit NewOwner(owner);
    }

    /// sets multiple values
    /// @dev used to set various config values
    /// @param _newPositionManager the new value for _newPositionManager
    /// @param _newQuoter the new value for uniswapQuoter
    /// @param _newToken0 the new value for _newToken0
    /// @param _newToken1 the new value for _newToken1
    /// @param _newFee the new value for _newFee
    function changePositionParameter(address _newPositionManager, address _newQuoter, address _newToken0, address _newToken1, uint24 _newFee) external onlyOwner {
        positionManager = INonfungiblePositionManager(_newPositionManager);
        uniswapV3Factory = IUniswapV3Factory(positionManager.factory());
        token0 = _newToken0;
        token1 = _newToken1;
        fee = _newFee;
        uniswapV3Pool = IUniswapV3Pool(uniswapV3Factory.getPool(token0, token1, fee));
        uniswapQuoter = IQuoter(_newQuoter);
    }

    /// sets the new yield manager
    /// @dev sets the value of the yield manager
    /// @param _newYieldManager the new value for _newYieldManager
    function changeYieldManager(address _newYieldManager) external onlyOwner {
        yieldManager = _newYieldManager;
        emit NewYieldManager(yieldManager);
    }

    /// sets the tick movement
    /// @dev sets the value of the tick movement
    /// @param _tickMovement the new value for _tickMovement
    function setTickMovement(int24 _tickMovement) external onlyOwner {
        tickMovement = _tickMovement;
        emit NewTickMovement(tickMovement);
    }

    /// sets the tick tickMoveThreshold
    /// @dev sets the value of the tickMoveThreshold
    /// @param _tickMoveThreshold the new value for _tickMoveThreshold
    function setTickMoveThreshold(int24 _tickMoveThreshold) external onlyOwner {
        tickMoveThreshold = _tickMoveThreshold;
        emit NewTickMoveThreshold(tickMoveThreshold);
    }

    /// sets the locked value
    /// @dev sets the value of isLocked and controls minting and increasing liquidity
    /// @param _locked the new value for _locked
    function setLocked(bool _locked) external onlyOwner {
        isLocked = _locked;
        emit Locked(_locked);
    }

    // default fallback and receive functions
    fallback() external payable {}
    receive() external payable {}
}

// interface for the YieldManager
interface IYieldManager {

    /// Sets the wanted affiliate
    /// @dev sets the value of the sponsor variable at a client object
    /// @param client the mapping entry point
    /// @param sponsor the address to set as a sponsor
    function setAffiliate(address client, address sponsor) external;

    /// Gets the factors for user and sponsor
    /// @dev returns the client and sponsor factors
    /// @param user the client to look up
    /// @param typer the type (sponsor or client mode)
    function getUserFactors(
        address user,
        uint typer
    ) external view returns (uint, uint, uint, uint);

    /// Gets the wanted affiliate
    /// @dev gets the value of the sponsor variable at a client object
    /// @param client the mapping entry point
    function getAffiliate(address client) external view returns (address);
}

