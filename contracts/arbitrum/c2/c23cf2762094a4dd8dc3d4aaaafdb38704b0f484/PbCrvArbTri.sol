// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./PbCrvBase.sol";
import "./IChainlink.sol";
import "./ISwapRouter.sol";
import "./IWETH.sol";
import "./IMinter.sol";

contract PbCrvArbTri is PbCrvBase {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable constant USDT = IERC20Upgradeable(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20Upgradeable constant WBTC = IERC20Upgradeable(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20Upgradeable constant WETH = IERC20Upgradeable(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IChainlink constant USDTPriceOracle = IChainlink(0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7);
    ISwapRouter constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IMinter constant minter = IMinter(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);

    function initialize(IERC20Upgradeable _rewardToken, address _treasury) external initializer {
        __Ownable_init();

        CRV = IERC20Upgradeable(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
        lpToken = IERC20Upgradeable(0x8e0B8c8BB9db49a46697F3a5Bb8A308e744821D2);
        rewardToken = _rewardToken;
        pool = IPool(0x960ea3e3C7FB317332d990873d354E18d7645590);
        gauge = IGauge(0x97E2768e8E73511cA874545DC5Ff8067eB19B787);
        treasury = _treasury;
        yieldFeePerc = 500;
        lendingPool = ILendingPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
        (,,,,,,,, address aTokenAddr) = lendingPool.getReserveData(address(rewardToken));
        aToken = IERC20Upgradeable(aTokenAddr);

        USDT.safeApprove(address(pool), type(uint).max);
        WBTC.safeApprove(address(pool), type(uint).max);
        WETH.safeApprove(address(pool), type(uint).max);
        lpToken.safeApprove(address(gauge), type(uint).max);
        lpToken.safeApprove(address(pool), type(uint).max);
        CRV.safeApprove(address(swapRouter), type(uint).max);
        rewardToken.safeApprove(address(lendingPool), type(uint).max);
    }

    function deposit(IERC20Upgradeable token, uint amount, uint amountOutMin) external payable override nonReentrant whenNotPaused {
        require(token == USDT || token == WBTC || token == WETH || token == lpToken, "Invalid token");
        require(amount > 0, "Invalid amount");

        uint currentPool = gauge.balanceOf(address(this));
        if (currentPool > 0) harvest();

        if (token == WETH) {
            require(msg.value == amount, "Invalid ETH");
            IWETH(address(WETH)).deposit{value: amount}();
        } else {
            token.safeTransferFrom(msg.sender, address(this), amount);
        }
        depositedBlock[msg.sender] = block.number;

        uint lpTokenAmt;
        if (token != lpToken) {
            uint[3] memory amounts;
            if (token == USDT) amounts[0] = amount;
            else if (token == WBTC) amounts[1] = amount;
            else amounts[2] = amount; // token == WETH
            pool.add_liquidity(amounts, amountOutMin);
            lpTokenAmt = lpToken.balanceOf(address(this));
        } else {
            lpTokenAmt = amount;
        }

        gauge.deposit(lpTokenAmt);
        User storage user = userInfo[msg.sender];
        user.lpTokenBalance += lpTokenAmt;
        user.rewardStartAt += (lpTokenAmt * accRewardPerlpToken / 1e36);

        emit Deposit(msg.sender, address(token), amount, lpTokenAmt);
    }

    function withdraw(IERC20Upgradeable token, uint lpTokenAmt, uint amountOutMin) external payable override nonReentrant {
        require(token == USDT || token == WBTC || token == WETH || token == lpToken, "Invalid token");
        User storage user = userInfo[msg.sender];
        require(lpTokenAmt > 0 && user.lpTokenBalance >= lpTokenAmt, "Invalid lpTokenAmt to withdraw");
        require(depositedBlock[msg.sender] != block.number, "Not allow withdraw within same block");

        claim();

        user.lpTokenBalance = user.lpTokenBalance - lpTokenAmt;
        user.rewardStartAt = user.lpTokenBalance * accRewardPerlpToken / 1e36;
        gauge.withdraw(lpTokenAmt);

        uint tokenAmt;
        if (token != lpToken) {
            uint i;
            if (token == USDT) i = 0;
            else if (token == WBTC) i = 1;
            else i = 2; // WETH
            pool.remove_liquidity_one_coin(lpTokenAmt, i, amountOutMin);
            tokenAmt = token.balanceOf(address(this));
        } else {
            tokenAmt = lpTokenAmt;
        }

        if (token == WETH) {
            IWETH(address(WETH)).withdraw(tokenAmt);
            (bool success,) = msg.sender.call{value: address(this).balance}("");
            require(success, "Failed transfer ETH");
        } else {
            token.safeTransfer(msg.sender, tokenAmt);
        }

        emit Withdraw(msg.sender, address(token), lpTokenAmt, tokenAmt);
    }

    receive() external payable {}

    function harvest() public override {
        // Update accrued amount of aToken
        uint allPool = getAllPool();
        uint aTokenAmt = aToken.balanceOf(address(this));
        if (aTokenAmt > lastATokenAmt) {
            uint accruedAmt = aTokenAmt - lastATokenAmt;
            accRewardPerlpToken += (accruedAmt * 1e36 / allPool);
            lastATokenAmt = aTokenAmt;
        }

        // gauge.claim_rewards();
        minter.mint(address(gauge));

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
            } else {
                rewardTokenAmt = _swap(rewardToken, CRVAmt);
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

            // Update accumulate reward token amount
            accRewardTokenAmt += rewardTokenAmt;

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

    function _swap(IERC20Upgradeable _rewardToken, uint amount) private returns (uint) {
        uint24 fee;
        if (_rewardToken == WBTC) fee = 3000;
        else if (_rewardToken == USDT) fee = 500;
        ISwapRouter.ExactInputParams memory params = 
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(address(CRV), uint24(10000), address(WETH), fee, address(_rewardToken)),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0
            });
        return swapRouter.exactInput(params);
    }

    function switchGauge() external onlyOwner {
        gauge.withdraw(gauge.balanceOf(address(this)));
        gauge = IGauge(0x555766f3da968ecBefa690Ffd49A2Ac02f47aa5f);
        lpToken.approve(address(gauge), type(uint).max);
        gauge.deposit(lpToken.balanceOf(address(this)));
    }

    function getPricePerFullShareInUSD() public view override returns (uint) {
        (, int answer,,,) = USDTPriceOracle.latestRoundData();
        // Get total USD for each asset (18 decimals)
        uint totalUSDTInUSD = pool.balances(0) * uint(answer) * 1e4;
        uint totalWBTCInUSD = pool.balances(1) * pool.price_oracle(0) / 1e8;
        uint totalWETHInUSD = pool.balances(2) * pool.price_oracle(1) / 1e18;
        uint totalAssetsInUSD = totalUSDTInUSD + totalWBTCInUSD + totalWETHInUSD;
        // Calculate price per full share
        return totalAssetsInUSD * 1e6 / lpToken.totalSupply(); // 6 decimals
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
        return gauge.claimable_tokens(address(this)); // crv, 18 decimals
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

