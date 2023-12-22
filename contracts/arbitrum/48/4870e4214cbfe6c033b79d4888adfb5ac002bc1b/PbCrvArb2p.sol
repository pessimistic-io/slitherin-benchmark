// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./PbCrvBase.sol";
import "./ISwapRouter.sol";

contract PbCrvArb2p is PbCrvBase {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable constant USDC = IERC20Upgradeable(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20Upgradeable constant USDT = IERC20Upgradeable(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20Upgradeable constant WETH = IERC20Upgradeable(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20Upgradeable constant WBTC = IERC20Upgradeable(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    ISwapRouter constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    function initialize(IERC20Upgradeable _rewardToken, address _treasury) external initializer {
        __Ownable_init();

        CRV = IERC20Upgradeable(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
        lpToken = IERC20Upgradeable(0x7f90122BF0700F9E7e1F688fe926940E8839F353);
        rewardToken = _rewardToken;
        pool = IPool(0x7f90122BF0700F9E7e1F688fe926940E8839F353);
        gauge = IGauge(0xbF7E49483881C76487b0989CD7d9A8239B20CA41);
        treasury = _treasury;
        yieldFeePerc = 500;
        lendingPool = ILendingPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
        (,,,,,,,, address aTokenAddr) = lendingPool.getReserveData(address(rewardToken));
        aToken = IERC20Upgradeable(aTokenAddr);

        USDC.safeApprove(address(pool), type(uint).max);
        USDT.safeApprove(address(pool), type(uint).max);
        lpToken.safeApprove(address(gauge), type(uint).max);
        lpToken.safeApprove(address(pool), type(uint).max);
        CRV.safeApprove(address(swapRouter), type(uint).max);
        rewardToken.safeApprove(address(lendingPool), type(uint).max);
    }

    function deposit(IERC20Upgradeable token, uint amount, uint amountOutMin) external override nonReentrant whenNotPaused {
        require(token == USDC || token == USDT || token == lpToken, "Invalid token");
        require(amount > 0, "Invalid amount");

        uint currentPool = gauge.balanceOf(address(this));
        if (currentPool > 0) harvest();

        token.safeTransferFrom(msg.sender, address(this), amount);
        depositedBlock[msg.sender] = block.number;

        uint lpTokenAmt;
        if (token != lpToken) {
            uint[2] memory amounts;
            if (token == USDC) amounts[0] = amount;
            else amounts[1] = amount; // token == USDT
            lpTokenAmt = pool.add_liquidity(amounts, amountOutMin);
        } else {
            lpTokenAmt = amount;
        }

        gauge.deposit(lpTokenAmt);
        User storage user = userInfo[msg.sender];
        user.lpTokenBalance += lpTokenAmt;
        user.rewardStartAt += (lpTokenAmt * accRewardPerlpToken / 1e36);

        emit Deposit(msg.sender, address(token), amount, lpTokenAmt);
    }

    function withdraw(IERC20Upgradeable token, uint lpTokenAmt, uint amountOutMin) external override nonReentrant {
        require(token == USDC || token == USDT || token == lpToken, "Invalid token");
        User storage user = userInfo[msg.sender];
        require(lpTokenAmt > 0 && user.lpTokenBalance >= lpTokenAmt, "Invalid lpTokenAmt to withdraw");
        require(depositedBlock[msg.sender] != block.number, "Not allow withdraw within same block");

        claim();

        user.lpTokenBalance = user.lpTokenBalance - lpTokenAmt;
        user.rewardStartAt = user.lpTokenBalance * accRewardPerlpToken / 1e36;
        gauge.withdraw(lpTokenAmt);

        uint tokenAmt;
        if (token != lpToken) {
            int128 i;
            if (token == USDC) i = 0;
            else i = 1; // USDT
            tokenAmt = pool.remove_liquidity_one_coin(lpTokenAmt, i, amountOutMin);
        } else {
            tokenAmt = lpTokenAmt;
        }
        token.safeTransfer(msg.sender, tokenAmt);

        emit Withdraw(msg.sender, address(token), lpTokenAmt, tokenAmt);
    }

    function harvest() public override {
        // Update accrued amount of aToken
        uint allPool = getAllPool();
        uint aTokenAmt = aToken.balanceOf(address(this));
        if (aTokenAmt > lastATokenAmt) {
            uint accruedAmt = aTokenAmt - lastATokenAmt;
            accRewardPerlpToken += (accruedAmt * 1e36 / allPool);
            lastATokenAmt = aTokenAmt;
        }

        gauge.claim_rewards();

        uint CRVAmt = CRV.balanceOf(address(this));
        if (CRVAmt > 1e18) {
            uint rewardTokenAmt;
            if (rewardToken == WETH) {
                ISwapRouter.ExactInputSingleParams memory params = 
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: address(CRV),
                        tokenOut: address(WETH),
                        fee: 10000,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: CRVAmt,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });
                rewardTokenAmt = swapRouter.exactInputSingle(params);
            } else { // rewardToken == WBTC
                ISwapRouter.ExactInputParams memory params = 
                    ISwapRouter.ExactInputParams({
                        path: abi.encodePacked(address(CRV), uint24(10000), address(WETH), uint24(3000), address(WBTC)),
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: CRVAmt,
                        amountOutMinimum: 0
                    });
                rewardTokenAmt = swapRouter.exactInput(params);
            }

            // Calculate fee
            uint fee = rewardTokenAmt * yieldFeePerc / 10000;
            rewardTokenAmt -= fee;
            rewardToken.safeTransfer(treasury, fee);

            // Update accRewardPerlpToken
            accRewardPerlpToken += (rewardTokenAmt * 1e36 / allPool);

            // Deposit reward token into Aave to get interest bearing aToken
            lendingPool.supply(address(rewardToken), rewardTokenAmt, address(this), 0);

            // Update lastATokenAmt
            lastATokenAmt = aToken.balanceOf(address(this));

            emit Harvest(CRVAmt, rewardTokenAmt, fee);
        }
    }

    function claim() public override {
        harvest();

        User storage user = userInfo[msg.sender];
        if (user.lpTokenBalance > 0) {
            // Calculate user reward
            uint aTokenAmt = (user.lpTokenBalance * accRewardPerlpToken / 1e36) - user.rewardStartAt;
            if (aTokenAmt > 0) {
                user.rewardStartAt += aTokenAmt;

                // Update lastATokenAmt
                if (lastATokenAmt >= aTokenAmt) {
                    lastATokenAmt -= aTokenAmt;
                } else {
                    // Last claim: to prevent arithmetic underflow error due to minor variation
                    lastATokenAmt = 0;
                }

                // Withdraw aToken to rewardToken
                uint aTokenBal = aToken.balanceOf(address(this));
                if (aTokenBal >= aTokenAmt) {
                    lendingPool.withdraw(address(rewardToken), aTokenAmt, address(this));
                } else {
                    // Last withdraw: to prevent withdrawal fail from lendingPool due to minor variation
                    lendingPool.withdraw(address(rewardToken), aTokenBal, address(this));
                }

                // Transfer rewardToken to user
                uint rewardTokenAmt = rewardToken.balanceOf(address(this));
                rewardToken.safeTransfer(msg.sender, rewardTokenAmt);

                emit Claim(msg.sender, rewardTokenAmt);
            }
        }
    }

    function getPricePerFullShareInUSD() public view override returns (uint) {
        return pool.get_virtual_price() / 1e12; // 6 decimals
    }

    function getAllPool() public view override returns (uint) {
        return gauge.balanceOf(address(this)); // lpToken, 18 decimals
    }

    function getAllPoolInUSD() external view override returns (uint) {
        uint allPool = getAllPool();
        if (allPool == 0) return 0;
        return allPool * getPricePerFullShareInUSD() / 1e18; // 6 decimals
    }

    /// @dev Call this function off-chain by using view
    function getPoolPendingReward() external override returns (uint) {
        return gauge.claimable_reward_write(address(this), address(CRV));
    }

    function getUserPendingReward(address account) external view override returns (uint) {
        User storage user = userInfo[account];
        return (user.lpTokenBalance * accRewardPerlpToken / 1e36) - user.rewardStartAt;
    }

    function getUserBalance(address account) external view override returns (uint) {
        return userInfo[account].lpTokenBalance;
    }

    function getUserBalanceInUSD(address account) external view override returns (uint) {
        return userInfo[account].lpTokenBalance * getPricePerFullShareInUSD() / 1e18;
    }
}

