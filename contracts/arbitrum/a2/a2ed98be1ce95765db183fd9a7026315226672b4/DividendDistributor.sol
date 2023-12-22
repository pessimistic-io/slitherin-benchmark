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
        address rewardToken;
        uint magnifiedDividendPerShare;
        mapping(address => int256) magnifiedDividendCorrections;
        mapping(address => uint256) withdrawnDividends;
    }

    function setTokenReward(Distributor storage distributor, address token) internal {
        distributor.rewardToken = token;
    }

    function withdrawable(Distributor storage distributor, address account, uint shares) internal view returns(uint256) {
        return (((distributor.magnifiedDividendPerShare * shares).toInt256() + distributor.magnifiedDividendCorrections[account]).toUint256())/PRECISION - distributor.withdrawnDividends[account];
    }

    function distribute(Distributor storage distributor, uint amount, uint totalShares) internal {
        if(totalShares > 0 && amount > 0) {
            distributor.magnifiedDividendPerShare += (amount * PRECISION) / totalShares;
            emit Distribution(distributor.rewardToken, amount);
        }
    }

    function withdraw(Distributor storage distributor, address account, uint shares) internal {
        uint256 _withdrawableDividend = withdrawable(distributor, account, shares);
        if (_withdrawableDividend > 0) {
            distributor.withdrawnDividends[account] += _withdrawableDividend;
        }
    }

    function transfer(Distributor storage distributor, address from, address to, uint value) internal {
        int256 _magCorrection = (distributor.magnifiedDividendPerShare * value).toInt256();
        distributor.magnifiedDividendCorrections[from] += _magCorrection;
        distributor.magnifiedDividendCorrections[to] -= _magCorrection;

    }

    function mint(Distributor storage distributor, address account, uint value) internal {
        distributor.magnifiedDividendCorrections[account] -= (distributor.magnifiedDividendPerShare * value).toInt256();
    }


    function burn(Distributor storage distributor, address account, uint value) internal {
        distributor.magnifiedDividendCorrections[account] += (distributor.magnifiedDividendPerShare * value).toInt256();
    }
}

