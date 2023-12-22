// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {Owned} from "./Owned.sol";
import "./IPool.sol";
import "./IPoolAddressesProvider.sol";
import "./IPoolDataProvider.sol";
import "./IAToken.sol";
import "./IYieldHandler.sol";

contract USDCHandler is IYieldHandler {

    address constant KEIMANAGER = 0xd26800A483A3A7181464023Ea19882d5e1c962f4;
    address constant POOLPROVIDER = 0xD64dDe119f11C88850FD596BE11CE398CC5893e6;
    address constant aUSDC = 0xC68eE187eb44227dCEaB89ce789193027887a30d;
    address constant USDC = 0xd513E4537510C75E24f941f159B7CAFA74E7B3B9;

    uint256 public deployedTokens;

    IPoolAddressesProvider private provider = IPoolAddressesProvider(0xD64dDe119f11C88850FD596BE11CE398CC5893e6);
    IPoolDataProvider private dataProvider = IPoolDataProvider(0x7E4025a4e9Ae4e7EcA533cDFF1ba269eDD31146F);
    IPool private lendingPool = IPool(provider.getPool());

    function deposit(address _from, uint256 _amount) public {
        ERC20(USDC).transferFrom(KEIMANAGER, address(this), _amount);
        ERC20(USDC).approve(address(lendingPool), _amount);

        lendingPool.deposit(USDC, _amount, KEIMANAGER, 0);
        deployedTokens += _amount;
    }

    function withdraw(address _from, uint256 _amount) public {
        ERC20(aUSDC).transferFrom(KEIMANAGER, address(this), _amount);
        ERC20(aUSDC).approve(address(lendingPool), _amount);

        lendingPool.withdraw(USDC, _amount, KEIMANAGER);
        deployedTokens -= _amount;
    }

    /*function getBalance(address _address) public view returns(uint256) {
        IAToken aToken = IAToken(aUSDC);
        uint256 aUSDCBalance = aToken.balanceOf(KEIMANAGER);
        (, , , , , , , , , uint256 liquidityIndex, , ) = dataProvider.getReserveData(USDC);
        
        if (aUSDCBalance == 0) {
            return 0;
        }

        uint256 currentUSDCValue = aUSDCBalance * liquidityIndex / 1e27;
        uint256 originalUSDCDeposited = deployedTokens;
        uint256 accruedUSDC = currentUSDCValue - originalUSDCDeposited;

        return currentUSDCValue * 10e12;
    }*/

    function getBalance(address _address) public view returns (uint256) {
        IAToken aToken = IAToken(aUSDC);
        uint256 aUSDCBalance = aToken.balanceOf(_address);
        
        (, , , , , , , , , uint256 liquidityIndex, , ) = dataProvider.getReserveData(USDC);
        
        // Adjust aUSDC balance to reflect current value in USDC
        uint256 currentUSDCValue = aUSDCBalance * liquidityIndex / 1e27;

        // Assuming you store the original USDC deposited in a variable `originalUSDCDeposited`
        uint256 originalUSDCDeposited = deployedTokens;

        // Calculate accrued interest
        uint256 accruedUSDC = currentUSDCValue - originalUSDCDeposited;

        //return (aUSDCBalance, liquidityIndex, currentUSDCValue, accruedUSDC);
        return currentUSDCValue;
    }
}
