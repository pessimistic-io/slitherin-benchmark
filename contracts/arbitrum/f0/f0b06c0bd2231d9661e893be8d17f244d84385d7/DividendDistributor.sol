//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20} from "./SafeERC20.sol";
import {SafeCast} from "./SafeCast.sol";

library DividendDistributor {
    using SafeCast for uint256;
    using SafeCast for int256;

    event Distribution(address _token, uint _amount);

    uint256 constant internal PRECISION = 2**128;

    struct Distributor {
        address _rewardToken;
        uint _magnifiedDividendPerShare;
        mapping(address => int256) _magnifiedDividendCorrections;
        mapping(address => uint256) _withdrawnDividends;
    }

    function setTokenReward(Distributor storage distributor, address token) internal {
        distributor._rewardToken = token;
    }

    function withdrawable(Distributor storage distributor, address account, uint shares) internal view returns(uint256) {
        return (((distributor._magnifiedDividendPerShare * shares).toInt256() + distributor._magnifiedDividendCorrections[account]).toUint256())/PRECISION - distributor._withdrawnDividends[account];
    }

    function distribute(Distributor storage distributor, uint amount, uint totalShares) internal {
        if(totalShares > 0 && amount > 0) {
            distributor._magnifiedDividendPerShare += (amount * PRECISION) / totalShares;
            emit Distribution(distributor._rewardToken, amount);
        }
    }

    function withdraw(Distributor storage distributor, address account, uint shares) internal returns(uint) {
        uint256 _withdrawableDividend = withdrawable(distributor , account, shares);
        if (_withdrawableDividend > 0) {
            distributor._withdrawnDividends[account] += _withdrawableDividend;
        }
        return _withdrawableDividend;
    }

    function transfer(Distributor storage distributor, address from, address to, uint value) internal {
        int256 _magCorrection = (distributor._magnifiedDividendPerShare * value).toInt256();
        distributor._magnifiedDividendCorrections[from] += _magCorrection;
        distributor._magnifiedDividendCorrections[to] -= _magCorrection;

    }

    function mint(Distributor storage distributor, address account, uint value) internal {
        distributor._magnifiedDividendCorrections[account] -= (distributor._magnifiedDividendPerShare * value).toInt256();
    }


    function burn(Distributor storage distributor, address account, uint value) internal {
        distributor._magnifiedDividendCorrections[account] += (distributor._magnifiedDividendPerShare * value).toInt256();
    }
}

