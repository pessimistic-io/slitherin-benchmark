// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./TransparentUpgradeableProxy.sol";
import "./IPriceRouter.sol";
import "./iTokenDForce.sol";
import "./iTokenWePiggy.sol";
import "./iTokenLodestar.sol";

//need to make the contract upgredable
contract PriceRouter is IPriceRouter {
    uint256 public routerDecimals = 18;

    address public usdt;
    address public usdc_e;
    address public wbtc;
    address public weth;
    address public arb;

    constructor(address _usdt, address _usdc_e, address _wbtc, address _weth, address _arb) {
        usdt = _usdt;
        usdc_e = _usdc_e;
        wbtc = _wbtc;
        weth = _weth;
        arb = _arb;
    }

    function getTokenPrice(address token, address itoken, uint256 amount) public view returns (uint256) {
        if (token == usdt) {
            //radiant V2
            if (itoken == address(bytes20(bytes("0xd69d402d1bdb9a2b8c3d88d98b9ceaf9e4cd72d9")))) {
                return amount;
            }
            //granary
            if (itoken == address(bytes20(bytes("0x66ddD8F3A0C4CEB6a324376EA6C00B4c8c1BB3d9")))) {
                return amount;
            }
            //AAVE V3
            if (itoken == address(bytes20(bytes("0x6ab707aca953edaefbc4fd23ba73294241490620")))) {
                return amount;
            }
            //dForce
            if (itoken == address(bytes20(bytes("0xf52f079Af080C9FB5AFCA57DDE0f8B83d49692a9")))) {
                return (amount * (10 ** routerDecimals)) / iTokenDForce(itoken).exchangeRateStored();
            }
            //wepiggy
            if (itoken == address(bytes20(bytes("0xB65Ab7e1c6c1Ba202baed82d6FB71975D56F007C")))) {
                return (amount * (10 ** routerDecimals)) / iTokenWePiggy(itoken).exchangeRateStored();
            }
            //lodestar
            if (itoken == address(bytes20(bytes("0xB65Ab7e1c6c1Ba202baed82d6FB71975D56F007C")))) {
                return (amount * (10 ** routerDecimals)) / iTokenLodestar(itoken).exchangeRateStored();
            }
        } else if (token == usdc_e) {
            //radiant V2
            if (itoken == address(bytes20(bytes("0x48a29e756cc1c097388f3b2f3b570ed270423b3d")))) {
                return amount;
            }
            //granary
            if (itoken == address(bytes20(bytes("0x48a29e756cc1c097388f3b2f3b570ed270423b3d")))) {
                return amount;
            }
            //AAVE V3
            if (itoken == address(bytes20(bytes("0x625E7708f30cA75bfd92586e17077590C60eb4cD")))) {
                return amount;
            }
            //dForce
            if (itoken == address(bytes20(bytes("0x8dc3312c68125a94916d62B97bb5D925f84d4aE0")))) {
                return (amount * (10 ** routerDecimals)) / iTokenDForce(itoken).exchangeRateStored();
            }
            //wepiggy
            if (itoken == address(bytes20(bytes("0x2Bf852e22C92Fd790f4AE54A76536c8C4217786b")))) {
                return (amount * (10 ** routerDecimals)) / iTokenWePiggy(itoken).exchangeRateStored();
            }
            //compound V3
            if (itoken == address(bytes20(bytes("0xa5edbdd9646f8dff606d7448e414884c7d905dca")))) {
                return 1;
            }
            //lodestar
            if (itoken == address(bytes20(bytes("0x1ca530f02DD0487cef4943c674342c5aEa08922F")))) {
                return (amount * (10 ** routerDecimals)) / iTokenLodestar(itoken).exchangeRateStored();
            }
        } else if (token == wbtc) {
            //radiant V2
            if (itoken == address(bytes20(bytes("0x727354712BDFcd8596a3852Fd2065b3C34F4F770")))) {
                return amount;
            }
            //granary V2
            if (itoken == address(bytes20(bytes("0x727354712BDFcd8596a3852Fd2065b3C34F4F770")))) {
                return amount;
            }
            //AAVE V3
            if (itoken == address(bytes20(bytes("0x078f358208685046a11C85e8ad32895DED33A249")))) {
                return amount;
            }
            //dForce
            if (itoken == address(bytes20(bytes("0xD3204E4189BEcD9cD957046A8e4A643437eE0aCC")))) {
                return (amount * (10 ** routerDecimals)) / iTokenDForce(itoken).exchangeRateStored();
            }
            //wepiggy
            if (itoken == address(bytes20(bytes("0x3393cD223f59F32CC0cC845DE938472595cA48a1")))) {
                return (amount * (10 ** routerDecimals)) / iTokenWePiggy(itoken).exchangeRateStored();
            }
            //lodestar
            if (itoken == address(bytes20(bytes("0xC37896BF3EE5a2c62Cdbd674035069776f721668")))) {
                return (amount * (10 ** routerDecimals)) / iTokenLodestar(itoken).exchangeRateStored();
            }
        } else if (token == weth) {
            //radiant V2
            if (itoken == address(bytes20(bytes("0x0dF5dfd95966753f01cb80E76dc20EA958238C46")))) {
                return amount;
            }
            //granary V2
            if (itoken == address(bytes20(bytes("0x0dF5dfd95966753f01cb80E76dc20EA958238C46")))) {
                return amount;
            }
            //AAVE V3
            if (itoken == address(bytes20(bytes("0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8")))) {
                return amount;
            }
            //wepiggy
            if (itoken == address(bytes20(bytes("0x17933112E9780aBd0F27f2B7d9ddA9E840D43159")))) {
                return (amount * (10 ** routerDecimals)) / iTokenWePiggy(itoken).exchangeRateStored();
            }
        }

        if (token == arb) {
            //radiant V2
            if (itoken == address(bytes20(bytes("0x2dADe5b7df9DA3a7e1c9748d169Cd6dFf77e3d01")))) {
                return amount;
            }
            //AAVE V3
            if (itoken == address(bytes20(bytes("0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8")))) {
                return amount;
            }
            //dForce
            if (itoken == address(bytes20(bytes("0x912CE59144191C1204E64559FE8253a0e49E6548")))) {
                return (amount * (10 ** routerDecimals)) / iTokenDForce(itoken).exchangeRateStored();
            }
            //lodestar
            if (itoken == address(bytes20(bytes("0x8991d64fe388fA79A4f7Aa7826E8dA09F0c3C96a")))) {
                return (amount * (10 ** routerDecimals)) / iTokenLodestar(itoken).exchangeRateStored();
            }
        }

        revert("Not supported token");
    }
}

