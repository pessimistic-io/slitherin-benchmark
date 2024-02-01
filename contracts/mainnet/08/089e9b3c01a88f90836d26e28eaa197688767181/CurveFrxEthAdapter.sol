// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IExchangeAdapter.sol";
import "./IWrappedEther.sol";

// solhint-disable func-name-mixedcase
// solhint-disable var-name-mixedcase
interface ICurveFrxEth {
    function add_liquidity(
        uint256[2] memory _amounts,
        uint256 _min_mint_amount
    ) external payable returns (uint256);

    function remove_liquidity_one_coin(
        uint256 _burn_amount,
        int128 i,
        uint256 _min_received
    ) external returns (uint256);
}

contract CurveFrxEthAdapter is IExchangeAdapter {
    address public constant FRX_ETH_LP =
        0xf43211935C781D5ca1a41d2041F397B8A7366C7A;

    function indexByCoin(address coin) public pure returns (int128) {
        if (coin == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) return 1; // WETH
        if (coin == 0x5E8422345238F34275888049021821E8E08CAa1f) return 2; // frxETH
        return 0;
    }

    // 0x6012856e  =>  executeSwap(address,address,address,uint256)
    function executeSwap(
        address pool,
        address fromToken,
        address toToken,
        uint256 amount
    ) external payable returns (uint256) {
        ICurveFrxEth curve = ICurveFrxEth(pool);
        if (toToken == FRX_ETH_LP) {
            uint128 i = uint128(indexByCoin(fromToken));
            require(i != 0, "CurveFrxEthAdapter: Can't Swap");
            if (i == 1) {
                IWrappedEther(fromToken).withdraw(amount);
            }
            uint256[2] memory entryVector;
            entryVector[i - 1] = amount;
            return curve.add_liquidity{value: amount}(entryVector, 0);
        } else if (fromToken == FRX_ETH_LP) {
            int128 i = indexByCoin(toToken);
            require(i != 0, "CurveFrxEthAdapter: Can't Swap");
            uint256 amount = curve.remove_liquidity_one_coin(amount, i - 1, 0);
            if (i == 1) {
                IWrappedEther(toToken).deposit{value: amount}();
            }
            return amount;
        } else {
            revert("CurveFrxEthAdapter: Can't Swap");
        }
    }

    // 0xe83bbb76  =>  enterPool(address,address,address,uint256)
    function enterPool(
        address,
        address,
        uint256
    ) external payable returns (uint256) {
        revert("CurveFrxEthAdapter: Can't Swap");
    }

    // 0x9d756192  =>  exitPool(address,address,address,uint256)
    function exitPool(
        address,
        address,
        uint256
    ) external payable returns (uint256) {
        revert("CurveFrxEthAdapter: Can't Swap");
    }
}

