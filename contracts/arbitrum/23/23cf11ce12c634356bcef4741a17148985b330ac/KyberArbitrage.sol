//SPDX-License-Identifier: Unlicense
//https://polygonscan.com/

pragma solidity ^0.8.4;
import "./console.sol";
import "./SafeERC20.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IERC20.sol";
import "./IPoolUniV2.sol";
import "./IPoolUniV3.sol";
import "./IPoolAddressesProvider.sol";
import "./SafeMath.sol";
import "./DexSwaps.sol";
import "./IPoolDODO.sol";
import "./IAsset.sol";
import "./IBalancerVault.sol";
import "./IPoolCurve.sol";
import "./IPoolSaddle.sol";
import "./IPoolMetavault.sol";
import "./IPoolAddressesProvider.sol";
import "./FlashLoanSimpleReceiverBase.sol";

contract KyberArbitrage is DexSwaps, FlashLoanSimpleReceiverBase {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    address public owner;
    address addressProvider;
    //Declare an Event
    event ArbitrageExecuted(
        address token,
        uint256 amountIn,
        uint256 amountOut,
        uint256 ratio,
        uint256 profit
    );

    constructor(
        address _addressProvider
    ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) {
        addressProvider = _addressProvider;
        owner = (msg.sender);
        console.log("create KyberArbitrage");
    }

    // ////////////////////////////ARBITRAGE
    function Arbitrage(
        bytes[] calldata encodedSwap,
        address tokenIn,
        uint256 amountIn
    ) external {
        bytes memory data = abi.encode(encodedSwap); // before flash loan
        // console.log(
        //     "BAlance antes del prestamo de usdt ",
        //     IERC20(tokenIn).balanceOf(address(this))
        // );
        // AAVE Flash Loan
        requestFlashLoan(data, tokenIn, amountIn);
    }

    // ////////////////////////////executeOperation

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address,
        bytes calldata params //mandar data
    ) external override returns (bool) {
        SwapInfo[6] memory swapInfoArray = SetSwapInfoArray(params); // in side Onflashloan  callback
        uint256 amountIn = amount;
        uint256 amountOwed = amount + premium;
        // console.log("amount in ", amountIn);
        // console.log(
        //     "ERC20(asset).balanceOf(address(this) ",
        //     IERC20(asset).balanceOf(address(this))
        // );
        // ExecuteSwaps
        for (uint8 i; i < swapInfoArray.length; i++) {
            console.log("i ", i);

            if (swapInfoArray[i].pool != address(0)) {
                amountIn = ExecuteSwap(swapInfoArray[i], amountIn);
            }
        }

        uint256 FinalBalance = amountIn;
        // uint256 FinalBalance = IERC20(asset).balanceOf(address(this)); ///////////////////// temporal

        // console.log("\n\n");
        // console.log("amount", amount);
        // console.log("premium", premium);
        // console.log("amountOwed", amountOwed);
        // console.log("FinalBalance", FinalBalance);

        require(FinalBalance > amountOwed, "Arbitrage not profitable");

        console.log("FinalBalance - amountOwed", FinalBalance - amountOwed);

        IERC20(asset).transfer(owner, FinalBalance - amountOwed);
        approveToken(asset, address(POOL));
        emit ArbitrageExecuted(
            asset,
            amount,
            FinalBalance,
            (FinalBalance * 1000000) / amount,
            FinalBalance - amount
        );
        return true;
    }

    ///////////////////// EXECUTE SWAP
    function ExecuteSwap(
        SwapInfo memory swapInfo,
        uint256 amountIn
    ) public returns (uint256) {
        // UNISWAP V2
        if (swapInfo.poolType == 0) {
            SwapUniswapV2(swapInfo, amountIn);
        }
        // UNISWAP V3
        else if (swapInfo.poolType == 1) {
            SwapUniswapV3(swapInfo, amountIn);
        }
        // // BALANCER
        else if (swapInfo.poolType == 2) {
            SwapBalancer(swapInfo, amountIn);
        }
        // // CURVE
        else if (swapInfo.poolType == 3) {
            SwapCurve(swapInfo, amountIn);
        }
        //DODO
        else if (swapInfo.poolType == 4) {
            SwapDodo(swapInfo, amountIn);
        }
        //DODO CLASSIC
        else if (swapInfo.poolType == 10) {
            SwapDodoClassic(swapInfo, amountIn);
        }
        // // KYBERSWAP V1
        else if (swapInfo.poolType == 5) {
            SwapKyberswapV1(swapInfo, amountIn);
        }
        // // KYBERSWAP V2
        else if (swapInfo.poolType == 6) {
            SwapKyberswapV2(swapInfo, amountIn);
        }
        // //METAVAULT
        else if (swapInfo.poolType == 7) {
            SwapMetavault(swapInfo, amountIn);
        }
        // // SADDLE
        else if (swapInfo.poolType == 8) {
            SwapSaddle(swapInfo, amountIn);
        }
        // VELODROME
        else if (swapInfo.poolType == 9) {
            SwapVelodrome(swapInfo, amountIn);
        }
        // //GMX
        else if (swapInfo.poolType == 11) {
            SwapGmx(swapInfo, amountIn);
        }
        uint256 balanceTokenOut = IERC20(swapInfo.tokenOut).balanceOf(
            address(this)
        );

        require(balanceTokenOut > 0, "Swap Failed");
        return balanceTokenOut;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the contract owner can call this function"
        );
        _;
    }

    function getBalanceOfToken(address _address) public view returns (uint256) {
        return IERC20(_address).balanceOf(address(this));
    }

    function testFunction() public pure returns (address) {
        return address(0);
    }

    function withdrawAll() public returns (address) {
        address[] memory tokens = tokensAAVE();
        for (uint256 i; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(tokens[i]).transfer(owner, balance);
            }
            // console.log("\n", tokens[i]);
            // console.log(balance);
        }

        return address(0);
    }

    function SetSwapInfoArray(
        bytes memory data
    ) internal pure returns (SwapInfo[6] memory) {
        bytes[] memory decodedSwap = abi.decode(data, (bytes[]));
        SwapInfo[6] memory swapInfoArray;

        for (uint8 i; i < decodedSwap.length; i++) {
            swapInfoArray[i] = decodeSwapInfo(decodedSwap[i]);
        }

        return swapInfoArray;
    }

    function decodeSwapInfo(
        bytes memory data
    ) public pure returns (SwapInfo memory) {
        (
            address pool,
            address tokenIn,
            address tokenOut,
            uint8 poolType,
            bytes32 poolId
        ) = abi.decode(data, (address, address, address, uint8, bytes32));

        SwapInfo memory swapInfo = SwapInfo(
            pool,
            tokenIn,
            tokenOut,
            poolType,
            poolId
        );
        return swapInfo;
    }

    ///////////////////// AAVE FLASHLOAN
    function requestFlashLoan(
        bytes memory data,
        address _token,
        uint256 _amount
    ) public {
        address reciverAddress = address(this);
        address asset = _token;
        uint256 amount = _amount;
        uint16 referralCode = 0; // ?

        POOL.flashLoanSimple(reciverAddress, asset, amount, data, referralCode);
    }

    ///////////////////// AAVE TOKENS
    function tokensAAVE() public view returns (address[] memory) {
        IPoolAddressesProvider.tokensAAVE[]
            memory list = IPoolAddressesProvider(
                IPoolAddressesProvider(addressProvider).getPoolDataProvider()
            ).getAllReservesTokens();

        address[] memory addressList = new address[](list.length);
        for (uint256 i; i < list.length; i++) {
            addressList[i] = list[i].token;
        }
        return addressList;
    }

    function contractBalance(
        address referenceToken,
        address factory
    ) external view returns (Balance[] memory) {
        console.log(referenceToken, factory);
        address[] memory tokens = tokensAAVE();
        console.log("Contract -  contractBalance tokensAAVE");

        Balance[] memory balances = new Balance[](tokens.length + 1);

        for (uint256 i; i < tokens.length; i++) {
            string memory symbol = IERC20(tokens[i]).symbol();
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            uint256 referenceBalance;
            if (referenceToken != tokens[i]) {
                referenceBalance = getAmountsOut(
                    factory,
                    balance,
                    tokens[i],
                    referenceToken
                );
            } else {
                referenceBalance = balance;
            }

            uint8 decimals = IERC20(tokens[i]).decimals();
            balances[i] = Balance(
                symbol,
                tokens[i],
                decimals,
                balance,
                referenceBalance
            );
        }

        uint256 totalBalanceUSD;
        for (uint256 i; i < tokens.length; i++) {
            // console.log("totalBalanceUSD", totalBalanceUSD);
            totalBalanceUSD = balances[i].balanceUSD + totalBalanceUSD;
        }

        // console.log("tokens.length + 1", tokens.length + 1);
        // console.log("decimals", IERC20(referenceToken).decimals());

        balances[tokens.length] = Balance(
            "TOTAL",
            address(0),
            IERC20(referenceToken).decimals(),
            totalBalanceUSD,
            totalBalanceUSD
        );

        return balances;
    }

    function getAmountsOut(
        address factory,
        uint amountIn,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 amountsOut) {
        address pool = IUniswapV2Factory(factory).getPair(tokenIn, tokenOut);
        // console.log("pool", pool);
        if (pool != address(0)) {
            (uint reserveIn, uint reserveOut, ) = IPoolUniV2(pool)
                .getReserves();
            uint amountInWithFee = amountIn.mul(997);
            uint numerator = amountInWithFee.mul(reserveOut);
            uint denominator = reserveIn.mul(1000).add(amountInWithFee);
            amountsOut = numerator / denominator;
        } else {
            amountsOut = 0;
        }
    }
}

