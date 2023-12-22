// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./IVeloPair.sol";
import "./IVeloRouter.sol";
import "./IVault.sol";
import "./IWETH.sol";

// import "forge-std/console2.sol";

contract BeefyWrapper {
    // Use SafeMath library for safe arithmetic operations
    using SafeMath for uint256;

    address public immutable admin;
    uint256 public fee;
    // address constant routerAddress = 0x9c12939390052919aF3155f41Bf4160Fd3666A6f;
    address public immutable wethAddress;

    uint256 constant minBalanceRequired = 0.003 ether;

    // IVeloRouter internal immutable router;
    IWETH public immutable weth;

    event FeeUpdated(uint256 v);
    event LogMessage(string m);

    modifier onlyOwner() {
        require(msg.sender == admin, "AD");
        _;
    }

    constructor(address _admin, address _wethAddress, uint256 _fee) {
        require(_admin != address(0), "A0");
        admin = _admin;
        fee = _fee;
        wethAddress = _wethAddress;
        weth = IWETH(_wethAddress);
        // router = IVeloRouter(routerAddress);
    }

    // address user, address token,
    function swapETHAndDeposit(
        address gaugeAddress,
        address pairAddress,
        address routerAddress,
        IVeloRouter.route[] calldata routes0,
        IVeloRouter.route[] calldata routes1
    ) external payable returns (uint256) {
        require(routes0.length >= 1 && routes1.length >= 1, "IP");
        uint256 etherAmount = msg.value;
        uint256 maxAmount = 2 ** 256 - 1;
        IVeloRouter router = IVeloRouter(routerAddress);

        // Get the pair details
        (, , , , bool stable, address token0, address token1) = IVeloPair(
            pairAddress
        ).metadata();

        // swap 50% ETH to token0
        // if token0 is WETH, then no need to swap
        if (token0 != wethAddress) {
            // console2.log("swap token0", token0, wethAddress);
            uint256[] memory expectedOutput0 = router.getAmountsOut(
                etherAmount.div(2),
                routes0
            );
            require(
                router
                .swapExactETHForTokens{value: etherAmount.div(2)}(
                    expectedOutput0[1],
                    routes0,
                    address(this),
                    block.timestamp
                ).length >= 2,
                "Revert due to swapExactETHForTokens0 failur"
            );
            emit LogMessage("swap token0");
        } else {
            // console2.log("deposit weth0");
            weth.deposit{value: etherAmount.div(2)}();
            require(weth.transfer(address(this), etherAmount.div(2)), "TF0");
            emit LogMessage("deposit weth0");
        }

        // swap 50% ETH to token1
        // if token1 is WETH, then no need to swap
        if (token1 != wethAddress) {
            // console2.log("swap token1");
            uint256[] memory expectedOutput1 = router.getAmountsOut(
                etherAmount.div(2),
                routes1
            );
            require(
                router
                .swapExactETHForTokens{value: etherAmount.div(2)}(
                    expectedOutput1[1],
                    routes1,
                    address(this),
                    block.timestamp
                ).length >= 2,
                "Revert due to swapExactETHForTokens1 failur"
            );
            emit LogMessage("swap token1");
        } else {
            // console2.log("deposit weth1");
            weth.deposit{value: etherAmount.div(2)}();
            require(weth.transfer(address(this), etherAmount.div(2)), "TF1");
            emit LogMessage("deposit weth1");
        }

        // get the token amounts
        uint256 token0Amount = IERC20(token0).balanceOf(address(this));
        uint256 token1Amount = IERC20(token1).balanceOf(address(this));

        // 1. Allow the router to spend the pairs
        require(IERC20(token0).approve(routerAddress, maxAmount), "A0");
        require(IERC20(token1).approve(routerAddress, maxAmount), "A1");
        // console2.log("approve router");
        // 2. add to liquidity the pairs using the router
        (uint256 estimateAmount0, uint256 estimateAmount1, ) = router
            .quoteAddLiquidity(
                token0,
                token1,
                stable,
                token0Amount,
                token1Amount
            );
        // console2.log("quoteAddLiquidity");
        (, , uint256 liquidity) = router.addLiquidity(
            token0,
            token1,
            stable,
            estimateAmount0,
            estimateAmount1,
            estimateAmount0.mul(98).div(100),
            estimateAmount1.mul(98).div(100),
            // msg.sender,
            address(this),
            block.timestamp
        );
        require(liquidity > 0, "LA");
        emit LogMessage("Added to liquidity");

        // 3. deposit the LP tokens to the vault
        require(IERC20(pairAddress).approve(gaugeAddress, maxAmount), "A0");
        IVault(gaugeAddress).depositAll();

        // 4. move the LP tokens to the user
        // console2.log("transfer liquidity to user");
        require(IERC20(gaugeAddress).approve(address(this), maxAmount), "A0");
        uint256 LpBalance = IERC20(gaugeAddress).balanceOf(address(this));
        bool success = IERC20(gaugeAddress).transferFrom(
            address(this),
            msg.sender,
            LpBalance
        );
        require(success, "LT");
        emit LogMessage("transfer liquidity to user");
        // console2.log("transfer liquidity to user");

        // if there is a balance in the contract of token0 then send it to the user
        uint256 token0Balance = IERC20(token0).balanceOf(address(this));
        if (token0Balance > 0) {
            require(IERC20(token0).transfer(msg.sender, token0Balance), "T06");
            emit LogMessage("transfer token0 balance to user");
        }
        // if there is a balance in the contract of token1 then send it to the user
        uint256 token1Balance = IERC20(token1).balanceOf(address(this));
        if (token1Balance > 0) {
            require(IERC20(token1).transfer(msg.sender, token1Balance), "T16");
            emit LogMessage("transfer token1 balance to user");
        }
        // if there is a balance in the contract of ETH then send it to the user
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            payable(msg.sender).transfer(ethBalance);
            emit LogMessage("transfer ETH balance to user");
        }
        return LpBalance;
    }

    function withdrawAndSwap(
        uint256 amount,
        uint256 rewards,
        address gaugeAddress,
        address pairAddress,
        address routerAddress,
        IVeloRouter.route[] calldata routes0,
        IVeloRouter.route[] calldata routes1
    ) external {
        require(routes0.length >= 1 && routes1.length >= 1, "IP");
        uint256 maxAmount = 2 ** 256 - 1;
        IVeloRouter router = IVeloRouter(routerAddress);

        // Get the pair details
        (, , , , bool stable, address token0, address token1) = IVeloPair(
            pairAddress
        ).metadata();

        // 1. Transfer mooTokens from the user to the contract
        bool success2 = IERC20(gaugeAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success2, "LT2");

        // 2. Withdraw the LP tokens from the vault
        IVault(gaugeAddress).withdraw(amount);

        // 3. Transfer fee service if rewards are greater than 0
        if (rewards > 0) {
            bool success = IERC20(pairAddress).transferFrom(
                msg.sender,
                0xc06323174D132363A3A1c36C8da7c7Cb7ceBb392,
                rewards.mul(fee).div(100)
            );
            require(success, "VT");
        }

        // 4. Allow the router to spend the LP tokens
        require(IERC20(pairAddress).approve(routerAddress, maxAmount), "RA");

        // 5. Withdraw tokens pair from liquidity using the router
        (uint256 estimateAmount0, uint256 estimateAmount1) = router
            .quoteRemoveLiquidity(token0, token1, stable, amount);
        (uint256 amount0, uint256 amount1) = router.removeLiquidity(
            token0,
            token1,
            stable,
            amount,
            estimateAmount0.mul(98).div(100),
            estimateAmount1.mul(98).div(100),
            address(this),
            block.timestamp
        );
        emit LogMessage("Removed liquidity");

        // 6. Allow the router to spend the pair
        require(IERC20(token0).approve(routerAddress, maxAmount), "TA0");
        require(IERC20(token1).approve(routerAddress, maxAmount), "TA1");

        // 7. swap the tokens for ETH and send it to the user
        // if token0 is WETH, then no need to swap
        if (token0 != wethAddress) {
            uint256[] memory expectedOutput0 = router.getAmountsOut(
                amount0,
                routes0
            );
            require(
                router
                    .swapExactTokensForETH(
                        amount0,
                        expectedOutput0[1],
                        routes0,
                        msg.sender,
                        block.timestamp
                    )
                    .length >= 2,
                "Revert due to swapExactETHForTokens0 failure"
            );
            emit LogMessage("Swap token0");
        } else {
            // if token0 is WETH, then send it to the user
            bool success = IERC20(wethAddress).transfer(msg.sender, amount0);
            require(success, "WT0");
            emit LogMessage("Withdraw WETH0");
        }

        // if token1 is WETH, then no need to swap
        if (token1 != wethAddress) {
            uint256[] memory expectedOutput1 = router.getAmountsOut(
                amount1,
                routes1
            );
            require(
                router
                    .swapExactTokensForETH(
                        amount1,
                        expectedOutput1[1],
                        routes1,
                        msg.sender,
                        block.timestamp
                    )
                    .length >= 2,
                "Revert due to swapExactETHForTokens1 failure"
            );
            emit LogMessage("Swap token1");
        } else {
            // if token1 is WETH, then send it to the user
            bool success = IERC20(wethAddress).transfer(msg.sender, amount1);
            require(success, "WT1");
            emit LogMessage("Withdraw WETH1");
        }

        // if there is a balance in the contract of token0 then send it to the user
        uint256 token0Balance = IERC20(token0).balanceOf(address(this));
        if (token0Balance > 0) {
            require(IERC20(token0).transfer(msg.sender, token0Balance), "T06");
            emit LogMessage("transfer token0 balance to user");
        }
        // if there is a balance in the contract of token1 then send it to the user
        uint256 token1Balance = IERC20(token1).balanceOf(address(this));
        if (token1Balance > 0) {
            require(IERC20(token1).transfer(msg.sender, token1Balance), "T16");
            emit LogMessage("transfer token1 balance to user");
        }
        // if there is a balance in the contract of ETH then send it to the user
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            payable(msg.sender).transfer(ethBalance);
            emit LogMessage("transfer ETH balance to user");
        }
    }

    function updateFee(uint256 newFee) external onlyOwner {
        require(newFee <= 50, "UF");
        fee = newFee;
        emit FeeUpdated(newFee);
    }

    function transferAll(address token) external onlyOwner {
        if (token == address(0)) {
            uint256 nativeBalance = address(this).balance;
            if (nativeBalance > 0) {
                payable(admin).transfer(nativeBalance);
            }
        } else {
            uint256 balance = IERC20(token).balanceOf(address(this));
            require(IERC20(token).transfer(admin, balance), "TAT");
        }
    }
}

