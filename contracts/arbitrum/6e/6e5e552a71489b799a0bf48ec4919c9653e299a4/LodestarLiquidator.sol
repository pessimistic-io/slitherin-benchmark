//SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./IFlashLoanRecipient.sol";
import "./UniswapV2Interface.sol";
import "./AggregatorV3Interface.sol";
import "./LiquidatorConstants.sol";
import "./Swap.sol";

contract LodestarLiquidator is ILiquidator, LiquidatorConstants, Ownable, IFlashLoanRecipient {
    uint256 constant BASE = 1e18;

    constructor(address[] memory lTokens, address[] memory underlyingTokens) {
        for (uint8 i = 0; i < lTokens.length; i++) {
            ICERC20(lTokens[i]).approve(lTokens[i], type(uint256).max);
        }
        for (uint8 i = 0; i < underlyingTokens.length; i++) {
            IERC20(underlyingTokens[i]).approve(address(lTokens[i]), type(uint256).max);
            IERC20(underlyingTokens[i]).approve(address(SUSHI_ROUTER), type(uint256).max);
            IERC20(underlyingTokens[i]).approve(address(UNI_ROUTER), type(uint256).max);
            IERC20(underlyingTokens[i]).approve(address(FRAX_ROUTER), type(uint256).max);
        }
        WETH.approve(address(SUSHI_ROUTER), type(uint256).max);
        WETH.approve(address(UNI_ROUTER), type(uint256).max);
        WETH.approve(address(FRAX_ROUTER), type(uint256).max);
        //WETH.approve(address(PLUTUS), type(uint256).max);
        WETH.approve(address(GLP), type(uint256).max);
        WETH.approve(address(this), type(uint256).max);
        GLP.approve(address(GLP_ROUTER), type(uint256).max);
        PLVGLP.approve(address(PLUTUS_DEPOSITOR), type(uint256).max);
    }

    event Liquidation(address borrower, address borrowMarket, address collateralMarket, uint256 repayAmountUSD);

    function swapThroughUniswap(
        address token0Address,
        address token1Address,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256) {
        uint24 poolFee = 3000;

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(token0Address, poolFee, token1Address),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });

        uint256 amountOut = UNI_ROUTER.exactInput(params);
        return amountOut;
    }

    //NOTE:Only involves swapping tokens for tokens, any operations involving ETH will be wrap/unwrap calls to WETH contract
    function swapThroughSushiswap(address token0Address, address token1Address, uint256 amountIn, uint256 minAmountOut) internal {
        address[] memory path = new address[](2);
        path[0] = token0Address;
        path[1] = token1Address;
        address to = address(this);
        uint256 deadline = block.timestamp;
        SUSHI_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, minAmountOut, path, to, deadline);
    }

    function swapThroughFraxswap(address token0Address, address token1Address, uint256 amountIn, uint256 minAmountOut) internal {
        address[] memory path = new address[](2);
        path[0] = token0Address;
        path[1] = token1Address;
        address to = address(this);
        uint256 deadline = block.timestamp;
        FRAX_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, minAmountOut, path, to, deadline);
    }

    //unwraps a position in plvGLP to native ETH, must be wrapped into WETH prior to repaying flash loan
    function unwindPlutusPosition() public {
        PLUTUS_DEPOSITOR.redeemAll();
        uint256 glpAmount = GLP.balanceOf(address(this));
        //TODO: update with a method to calculate minimum out given 2.5% slippage constraints.
        uint256 minOut = 0;
        GLP_ROUTER.unstakeAndRedeemGlp(address(WETH), glpAmount, minOut, address(this));
    }

    function plutusRedeem() public {
        PLUTUS_DEPOSITOR.redeemAll();
    }

    function glpRedeem() public {
        uint256 balance = GLP.balanceOf(address(this));
        GLP_ROUTER.unstakeAndRedeemGlp(address(WETH), balance, 0, address(this));
    }

    function wrapEther(uint256 amount) public returns (uint256) {
        address _owner = owner();
        require(msg.sender == _owner || msg.sender == address(this), "UNAUTHORIZED");
        (bool sent, ) = address(WETH).call{value: amount}("");
        require(sent, "Failed to send Ether");
        uint256 wethAmount = WETH.balanceOf(address(this));
        return wethAmount;
    }

    function unwrapEther(uint256 amountIn) public returns (uint256) {
        address _owner = owner();
        require(msg.sender == _owner || msg.sender == address(this), "UNAUTHORIZED");
        WETH.withdraw(amountIn);
        uint256 etherAmount = address(this).balance;
        return etherAmount;
    }

    function withdrawWETH() external onlyOwner {
        uint256 amount = WETH.balanceOf(address(this));
        WETH.transferFrom(address(this), msg.sender, amount);
    }

    function withdrawETH() external payable onlyOwner {
        uint256 balance = address(this).balance;
        (bool sent, ) = msg.sender.call{value: balance}("");
        require(sent, "Failed to send Ether");
    }

    receive() external payable {}

    //TODO:Updates for migration to WETH flash loans, swaps to/from WETH for liquidations and repayment, check for special swap cases

    function liquidateAccount(
        address borrowerAddress,
        ICERC20 borrowMarket,
        IERC20[] memory tokens,
        uint256[] memory loanAmounts,
        ICERC20 collateralMarket
    ) external {
        require(tx.origin == msg.sender, "Cannot be called by Smart Contracts");
        require(WETH.balanceOf(address(BALANCER_VAULT)) > loanAmounts[0], "Not enough liquidity in Balancer Pool");

        LiquidationData memory liquidationData = LiquidationData({
            user: borrowerAddress,
            borrowMarketAddress: borrowMarket,
            loanAmount: loanAmounts[0],
            collateralMarketAddress: collateralMarket
        });

        BALANCER_VAULT.flashLoan(IFlashLoanRecipient(address(this)), tokens, loanAmounts, abi.encode(liquidationData));
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory liquidationData
    ) external override {
        if (msg.sender != address(BALANCER_VAULT)) revert UNAUTHORIZED("!vault");

        // additional checks?

        LiquidationData memory data = abi.decode(liquidationData, (LiquidationData));
        if (data.loanAmount != amounts[0] || WETH != tokens[0]) revert FAILED("!chk");

        // sanity check: flashloan has no fees
        if (feeAmounts[0] > 0) revert FAILED("fee>0");

        address borrower = data.user;
        ICERC20 borrowMarketAddress = data.borrowMarketAddress;
        ICERC20 collateralMarketAddress = data.collateralMarketAddress;

        string memory borrowMarketSymbol = borrowMarketAddress.symbol();
        string memory collateralMarketSymbol = collateralMarketAddress.symbol();

        IERC20 borrowUnderlyingAddress;
        IERC20 collateralUnderlyingAddress;

        if(keccak256(bytes(borrowMarketSymbol)) != keccak256("lETH")) {
            borrowUnderlyingAddress = IERC20(borrowMarketAddress.underlying());
        }

        if(keccak256(bytes(collateralMarketSymbol)) != keccak256("lETH")) {
            collateralUnderlyingAddress = IERC20(collateralMarketAddress.underlying());
        }
        //so now we have the WETH to liquidate in hand and now need to swap to the appropriate borrowed asset and execute the liquidation
        

        if (keccak256(bytes(borrowMarketSymbol)) == keccak256("lETH")) {
            uint256 wethBalance = WETH.balanceOf(address(this));
            unwrapEther(wethBalance);
            uint256 repayAmount = address(this).balance;
            require(repayAmount != 0, "Swap Failed");
            ICETH cEth = ICETH(address(borrowMarketAddress));
            cEth.liquidateBorrow{value: repayAmount}(borrower, collateralMarketAddress);
            emit Liquidation(borrower, address(borrowMarketAddress), address(collateralMarketAddress), repayAmount);
        } else if (keccak256(bytes(borrowMarketSymbol)) == keccak256("lUSDC")) {
            uint256 wethBalance = WETH.balanceOf(address(this));
            swapThroughUniswap(address(WETH), address(borrowUnderlyingAddress), wethBalance, 0);
            uint256 repayAmount = borrowUnderlyingAddress.balanceOf(address(this));
            require(repayAmount != 0, "Swap Failed");
            borrowMarketAddress.liquidateBorrow(borrower, repayAmount, address(collateralMarketAddress));
            emit Liquidation(borrower, address(borrowMarketAddress), address(collateralMarketAddress), repayAmount);
        } else if (keccak256(bytes(borrowMarketSymbol)) == keccak256("lARB")) {
            uint256 wethBalance = WETH.balanceOf(address(this));
            swapThroughUniswap(address(WETH), address(borrowUnderlyingAddress), wethBalance, 0);
            uint256 repayAmount = borrowUnderlyingAddress.balanceOf(address(this));
            require(repayAmount != 0, "Swap Failed");
            borrowMarketAddress.liquidateBorrow(borrower, repayAmount, address(collateralMarketAddress));
            emit Liquidation(borrower, address(borrowMarketAddress), address(collateralMarketAddress), repayAmount);
        } else if (keccak256(bytes(borrowMarketSymbol)) == keccak256("lWBTC")) {
            uint256 wethBalance = WETH.balanceOf(address(this));
            swapThroughUniswap(address(WETH), address(borrowUnderlyingAddress), wethBalance, 0);
            uint256 repayAmount = borrowUnderlyingAddress.balanceOf(address(this));
            require(repayAmount != 0, "Swap Failed");
            borrowMarketAddress.liquidateBorrow(borrower, repayAmount, address(collateralMarketAddress));
            emit Liquidation(borrower, address(borrowMarketAddress), address(collateralMarketAddress), repayAmount);
        } else if (keccak256(bytes(borrowMarketSymbol)) == keccak256("lDAI")) {
            uint256 wethBalance = WETH.balanceOf(address(this));
            swapThroughUniswap(address(WETH), address(borrowUnderlyingAddress), wethBalance, 0);
            uint256 repayAmount = borrowUnderlyingAddress.balanceOf(address(this));
            require(repayAmount != 0, "Swap Failed");
            borrowMarketAddress.liquidateBorrow(borrower, repayAmount, address(collateralMarketAddress));
            emit Liquidation(borrower, address(borrowMarketAddress), address(collateralMarketAddress), repayAmount);
        } else if (keccak256(bytes(borrowMarketSymbol)) == keccak256("lUSDT")) {
            uint256 wethBalance = WETH.balanceOf(address(this));
            swapThroughUniswap(address(WETH), address(borrowUnderlyingAddress), wethBalance, 0);
            uint256 repayAmount = borrowUnderlyingAddress.balanceOf(address(this));
            require(repayAmount != 0, "Swap Failed");
            borrowMarketAddress.liquidateBorrow(borrower, repayAmount, address(collateralMarketAddress));
            emit Liquidation(borrower, address(borrowMarketAddress), address(collateralMarketAddress), repayAmount);
        } else if (keccak256(bytes(borrowMarketSymbol)) == keccak256("lMAGIC")) {
            uint256 wethBalance = WETH.balanceOf(address(this));
            swapThroughSushiswap(address(WETH), address(borrowUnderlyingAddress), wethBalance, 0);
            uint256 repayAmount = borrowUnderlyingAddress.balanceOf(address(this));
            require(repayAmount != 0, "Swap Failed");
            borrowMarketAddress.liquidateBorrow(borrower, repayAmount, address(collateralMarketAddress));
            emit Liquidation(borrower, address(borrowMarketAddress), address(collateralMarketAddress), repayAmount);
        } else if (keccak256(bytes(borrowMarketSymbol)) == keccak256("lDPX")) {
            uint256 wethBalance = WETH.balanceOf(address(this));
            swapThroughSushiswap(address(WETH), address(borrowUnderlyingAddress), wethBalance, 0);
            uint256 repayAmount = borrowUnderlyingAddress.balanceOf(address(this));
            require(repayAmount != 0, "Swap Failed");
            borrowMarketAddress.liquidateBorrow(borrower, repayAmount, address(collateralMarketAddress));
            emit Liquidation(borrower, address(borrowMarketAddress), address(collateralMarketAddress), repayAmount);
        } else {
            uint256 wethBalance = WETH.balanceOf(address(this));
            swapThroughFraxswap(address(WETH), address(borrowUnderlyingAddress), wethBalance, 0);
            uint256 repayAmount = borrowUnderlyingAddress.balanceOf(address(this));
            require(repayAmount != 0, "Swap Failed");
            borrowMarketAddress.liquidateBorrow(borrower, repayAmount, address(collateralMarketAddress));
            emit Liquidation(borrower, address(borrowMarketAddress), address(collateralMarketAddress), repayAmount);
        }

        uint256 lTokenBalance = collateralMarketAddress.balanceOf(address(this));

        collateralMarketAddress.redeem(lTokenBalance);

        if (keccak256(bytes(collateralMarketSymbol)) == keccak256("lETH")) {
            uint256 etherBalance = address(this).balance;
            wrapEther(etherBalance);
        } else if (keccak256(bytes(collateralMarketSymbol)) == keccak256("lUSDC")) {
            uint256 collateralBalance = collateralUnderlyingAddress.balanceOf(address(this));
            swapThroughUniswap(address(collateralUnderlyingAddress), address(WETH), collateralBalance, 0);
        } else if (keccak256(bytes(collateralMarketSymbol)) == keccak256("lARB")) {
            uint256 collateralBalance = collateralUnderlyingAddress.balanceOf(address(this));
            swapThroughUniswap(address(collateralUnderlyingAddress), address(WETH), collateralBalance, 0);
        } else if (keccak256(bytes(collateralMarketSymbol)) == keccak256("lWBTC")) {
            uint256 collateralBalance = collateralUnderlyingAddress.balanceOf(address(this));
            swapThroughUniswap(address(collateralUnderlyingAddress), address(WETH), collateralBalance, 0);
        } else if (keccak256(bytes(collateralMarketSymbol)) == keccak256("lDAI")) {
            uint256 collateralBalance = collateralUnderlyingAddress.balanceOf(address(this));
            swapThroughUniswap(address(collateralUnderlyingAddress), address(WETH), collateralBalance, 0);
        } else if (keccak256(bytes(collateralMarketSymbol)) == keccak256("lUSDT")) {
            uint256 collateralBalance = collateralUnderlyingAddress.balanceOf(address(this));
            swapThroughUniswap(address(collateralUnderlyingAddress), address(WETH), collateralBalance, 0);
        } else if (keccak256(bytes(collateralMarketSymbol)) == keccak256("lMAGIC")) {
            uint256 collateralBalance = collateralUnderlyingAddress.balanceOf(address(this));
            swapThroughSushiswap(address(collateralUnderlyingAddress), address(WETH), collateralBalance, 0);
        } else if (keccak256(bytes(collateralMarketSymbol)) == keccak256("lDPX")) {
            uint256 collateralBalance = collateralUnderlyingAddress.balanceOf(address(this));
            swapThroughSushiswap(address(collateralUnderlyingAddress), address(WETH), collateralBalance, 0);
        } else if (keccak256(bytes(collateralMarketSymbol)) == keccak256("lFRAX")) {
            uint256 collateralBalance = collateralUnderlyingAddress.balanceOf(address(this));
            swapThroughFraxswap(address(collateralUnderlyingAddress), address(WETH), collateralBalance, 0);
        } else {
            unwindPlutusPosition();
        }

        WETH.transferFrom(address(this), msg.sender, amounts[0]);
    }
}

