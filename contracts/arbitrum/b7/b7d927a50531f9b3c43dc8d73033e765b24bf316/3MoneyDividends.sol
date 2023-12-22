// SPDX-License-Identifier: BSD

pragma solidity ^0.8.17;

import "./DividendPayingToken.sol";
import "./IterableMapping.sol";
import "./3Money.sol";
import "./IBalanceSetter.sol";

contract _3MoneyDividends is DividendPayingToken {
    using IterableMapping for IterableMapping.Map;

    event DividendWithdrawn(
        address indexed to,
        uint256 value,
        bool automatic
    );

    modifier onlyBalanceSetter() {
        require(address(balanceSetter) == msg.sender, "onlyBalanceSetter");
        _;
    }

    modifier onlyTokenOwner() {
        require(token.owner() == msg.sender, "onlyTokenOwner");
        _;
    }

    _3Money token;
    IBalanceSetter balanceSetter;
    uint256 dailyRewards;
    uint256 lastRewardMintTime;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;
    uint256 public startTime;

    mapping (address => bool) public excludedFromDividends;

    uint256 public immutable minimumTokenBalanceForDividends = 0.01 ether;

    event ExcludeFromDividends(address indexed account);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);


    constructor(string memory name, address _token, address rewardToken, address _balanceSetter) DividendPayingToken(name, name, IERC20(rewardToken)) {
        token = _3Money(payable(_token));
        balanceSetter = IBalanceSetter(_balanceSetter);
        dailyRewards = 27.39726 ether;
    }

    function setDailyRewards(uint256 amount) external onlyTokenOwner {
        dailyRewards = amount;
    }

    function updateBalanceSetter(address newBalanceSetter) external onlyTokenOwner {
        balanceSetter = IBalanceSetter(newBalanceSetter);
    }

    function excludeFromDividends(address account) external onlyOwner {
        if(account == address(0)) {
            return;
        }
    	excludedFromDividends[account] = true;

    	_setBalance(account, 0);
    	tokenHoldersMap.remove(account);

    	emit ExcludeFromDividends(account);
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }

    function accountData(address account) public view returns (uint256[] memory dividendInfo) {
        dividendInfo = new uint256[](14);

        uint256 balance = balanceOf(account);
        dividendInfo[0] = balance;
        uint256 totalSupply = totalSupply();
        dividendInfo[1] = totalSupply > 0 ? balance * 1000000 / totalSupply : 0;
        dividendInfo[2] = totalSupply;

        uint256 withdrawableDividends = withdrawableDividendOf(account);
        uint256 totalDividends = accumulativeDividendOf(account);

        dividendInfo[3] = withdrawableDividends;
        dividendInfo[4] = totalDividends;
        dividendInfo[5] = totalDividendsDistributed;
        dividendInfo[6] = estimatedWeeklyDividends();

        uint256 day = block.timestamp / 1 days;

        for(uint256 i = 0; i < 7; i++) {
            dividendInfo[7 + i] = totalDividendsDistributedByDay[day - i];
        }
    }

    function estimatedWeeklyDividends() public view returns (uint256) {
        if(startTime == 0) {
            return 0;
        }

        uint256 elapsed = block.timestamp - startTime;
        if(elapsed == 0) {
            return 0;
        }

        uint256 oneWeek = 7 days;
        if(elapsed < oneWeek) {
            return totalDividendsDistributed * oneWeek / elapsed;
        }

        uint256 day = block.timestamp / 1 days;
        uint256 totalInLastWeek = 0;
        for(uint256 i = 0; i < 7; i++) {
            if(i == 0) {
                uint256 today = totalDividendsDistributedByDay[day];
                elapsed = block.timestamp - (day * 1 days);
                totalInLastWeek += today * 1 days / elapsed;
            }
            else {
                totalInLastWeek += totalDividendsDistributedByDay[day - i];
            }
        }

        return totalInLastWeek;
    }


    function accountDataAtIndex(uint256 index)
        public view returns (uint256[] memory) {
    	if(index >= tokenHoldersMap.size()) {
            return new uint256[](5);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return accountData(account);
    }

    function canAutoClaim(address account) private view returns (bool) {
        uint256 withdrawable = withdrawableDividendOf(account);

        return withdrawable >= 0.00001 ether;
    }

    function setBalance(address payable account, uint256 newBalance) public {
        require(msg.sender == address(balanceSetter) || msg.sender == owner(), "Cannot call");

    	if(excludedFromDividends[account]) {
    		return;
    	}

    	if(newBalance >= minimumTokenBalanceForDividends) {
            if(startTime == 0) {
                startTime = block.timestamp;
            }
            _setBalance(account, newBalance);
    		tokenHoldersMap.set(account, newBalance);
    	}
    	else {
            _setBalance(account, 0);
    		tokenHoldersMap.remove(account);
    	}

    	_claimDividends(account, false);
    }

    function handleTokenBalancesUpdated(address account1, address account2) external onlyOwner {
        uint256 dividendBalance = balanceSetter.getDividendBalance(address(this), account1);
        setBalance(payable(account1), dividendBalance);
        dividendBalance = balanceSetter.getDividendBalance(address(this), account2);
        setBalance(payable(account2), dividendBalance);
    }

    function process(uint256 gas) public returns (uint256, uint256, uint256) {
    	uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

    	if(numberOfTokenHolders == 0) {
    		return (0, 0, lastProcessedIndex);
    	}

        if(address(rewardToken) != address(0)) {
            if(lastRewardMintTime == 0) {
                lastRewardMintTime = block.timestamp;
            }

            uint256 elapsed = block.timestamp - lastRewardMintTime;

            if(elapsed >= 10 minutes) {
                uint256 mint = dailyRewards * elapsed / 1 days;

                try token.mintTokens(mint, address(this)) {
                    distributeDividends(mint);
                }
	    	    catch {
                    //main contract limit hit for day
                }

                lastRewardMintTime = block.timestamp;
            }
        }

    	uint256 _lastProcessedIndex = lastProcessedIndex;

    	uint256 gasUsed = 0;

    	uint256 gasLeft = gasleft();

    	uint256 iterations = 0;
    	uint256 claims = 0;

    	while(gasUsed < gas && iterations < numberOfTokenHolders) {
    		_lastProcessedIndex++;

    		if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
    			_lastProcessedIndex = 0;
    		}

    		address account = tokenHoldersMap.keys[_lastProcessedIndex];

    		if(canAutoClaim(account)) {
    			if(_claimDividends(payable(account), true)) {
    				claims++;
    			}
    		}
            else {
                token.burnForAccount(account);
            }

            uint256 newBalance = balanceSetter.getDividendBalance(address(this), account);

            if(newBalance >= minimumTokenBalanceForDividends) {
                _setBalance(account, newBalance);
    	    }
    	    else {
                _setBalance(account, 0);
    		    tokenHoldersMap.remove(account);

                if(tokenHoldersMap.keys.length == 0) {
                    break;
                }

                if(_lastProcessedIndex == 0) {
                    _lastProcessedIndex = tokenHoldersMap.keys.length - 1;
                }
                else {
                    _lastProcessedIndex--;
                }
    	    }

    		iterations++;

    		uint256 newGasLeft = gasleft();

    		if(gasLeft > newGasLeft) {
    			gasUsed = gasUsed + (gasLeft - newGasLeft);
    		}

    		gasLeft = newGasLeft;
    	}

    	lastProcessedIndex = _lastProcessedIndex;

    	return (iterations, claims, lastProcessedIndex);
    }

    function claimDividends(address account) public returns (bool) {
        require(msg.sender == owner() || msg.sender == account, "Invalid account");
        return _claimDividends(account, false);
    }

    function _claimDividends(address account, bool automatic) private returns (bool) {
        uint256 amount = withdrawableDividendOf(account);

        token.burnForAccount(account);

    	if(amount > 0) {
            withdrawnDividends[account] += amount;

            if(address(rewardToken) == address(0)) {
                (bool success,) = payable(account).call{value: amount, gas: 4000}("");

                if(!success) {
                    withdrawnDividends[account] -= amount;
                    return false;
                }
            }
            else {
                rewardToken.transfer(account, amount);
            }

            emit DividendWithdrawn(account, amount, automatic);
    		return true;
    	}

    	return false;
    }
}


