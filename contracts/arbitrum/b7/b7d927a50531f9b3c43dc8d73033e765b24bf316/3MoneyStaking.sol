// SPDX-License-Identifier: BSD

import "./Uniswap.sol";
import "./Ownable.sol";
import "./3Money.sol";
import "./3MoneyDividends.sol";
import "./ERC20.sol";
import "./IBalanceSetter.sol";

pragma solidity ^0.8.17;

contract _3MoneyStaking is Ownable, IBalanceSetter {
    struct StakeType {
        bool isLiquidity;
        uint256 duration; //In days
        uint256 multiplier;
        bool giveTokenDividends;
    }

    struct Stake {
        uint256 key;
        address account;
        uint256 startTime;
        uint256 stakedTokens;
        uint256 dividendTokensETH;
        uint256 dividendTokensToken;
    }

    _3Money public token;

    bool public enabled;
    
    mapping (uint256 => StakeType) public stakeTypes;
    mapping (uint256 =>  uint256) public stakeTypeStakedAmount;

    mapping (address =>  mapping (uint256 => Stake)) public stakes;

    mapping (address =>  uint256) public accountStakedTokens;
    mapping (address =>  uint256) public accountStakedLiquidityTokens;
    mapping (address =>  uint256) public accountDividendTokensETH;
    mapping (address =>  uint256) public accountDividendTokensToken;

    event StakeTypeAdded(bool isLiquidity, uint256 duration, uint256 multiplier, bool giveTokenDividends);

    event TokensStaked(address indexed account, uint256 indexed key, uint256 amount, bool newStake, bool zap);
    event TokensUnstaked(address indexed account, uint256 indexed key, uint256 amount, bool full);

    receive() external payable {}

    modifier onlyEnabled() {
        require(enabled, "not enabled");
        _;
    }

    constructor(address _token) {
        token = _3Money(payable(_token));

        addStakeType(false, 7, 10, false);
        addStakeType(false, 30, 30, false);
        addStakeType(false, 90, 60, true);
        addStakeType(true, 30, 60, true);
    }

    function getDividendBalance(address dividendContract, address account) public view returns (uint256) {
        if(dividendContract == address(token.dividendsETH())) {
            if(enabled) {
                return accountDividendTokensETH[account];
            }
            return token.balanceOf(account);
        }
        if(dividendContract == address(token.dividendsTokens())) {
            if(enabled) {
                return accountDividendTokensToken[account];
            }
        }
        return 0;
    }

    function setEnabled(bool _enabled) external onlyOwner {
        enabled = _enabled;
    }

    function getKey(bool isLiquidity, uint256 duration) public pure returns (uint256) {
        uint256 key = duration;

        if(isLiquidity) {
            key += 1000;
        }

        return key;
    }

    function addStakeType(bool isLiquidity, uint256 duration, uint256 multiplier, bool giveTokenDividends) public onlyOwner {
        uint256 key = getKey(isLiquidity, duration);

        require(stakeTypes[key].duration == 0, "Already added");
        require(duration >= 1 && duration < 1000, "Invalid duration");
        require(multiplier >= 1 && multiplier <= 1000, "Invalid multiplier");

        stakeTypes[key] = StakeType(isLiquidity, duration, multiplier, giveTokenDividends);

        emit StakeTypeAdded(isLiquidity, duration, multiplier, giveTokenDividends);
    }

    function updateStakeType(uint256 key, uint256 multiplier) external onlyOwner {
        StakeType storage stakeType = stakeTypes[key];
        require(stakeType.duration > 0, "Invalid stake type");

        require(multiplier >= 1 && multiplier <= 1000, "Invalid multiplier");

        stakeType.multiplier = multiplier;
    }

    function stakeTokens(uint256 key, uint256 amount) external onlyEnabled {
        StakeType storage stakeType = stakeTypes[key];
        require(!stakeType.isLiquidity, "Use performZap to stake liquidity");
        _stakeTokens(key, amount, amount, msg.sender);
    }

    function stakeTokensFor(uint256 key, uint256 amount, address account) external onlyEnabled {
        require(msg.sender == address(token), "Only token can call this");
        _stakeTokens(key, amount, amount, account);
    }

    //When it's liquidity, amount will be 2x the number of tokens in the liquidity
    //being added
    function _stakeTokens(uint256 key, uint256 stakedTokens, uint256 amount, address account) private {
        require(enabled, "not enabled");
        //require(msg.sender == account || msg.sender == address(this), "Invalid account");
        require(amount > 0, "Invalid amount");

        StakeType storage stakeType = stakeTypes[key];
        require(stakeType.duration > 0, "Invalid stake type");

        Stake storage stake = stakes[account][key];

        bool newStake = false;

        //Nothing currently staked here
        if(stake.key == 0) {
            stake.key = key;
            stake.account = account;
            newStake = true;
        }

        if(stake.startTime == 0 || msg.sender != address(token)) {
            stake.startTime = block.timestamp;
        }

        if(!stakeType.isLiquidity) {
            require(stakedTokens == amount, "stakedTokens must be same as amount");
            if(msg.sender != address(this)) {
                require(token.balanceOf(account) >= amount, "Insufficient balance");
                uint256 balanceBefore = token.balanceOf(address(this));
                token.transferFrom(account, address(this), amount);
                amount = token.balanceOf(address(this)) - balanceBefore;
                stakedTokens = amount;
            }
        }
        /*
        else {
            require(msg.sender == address(this), "Only contract itself can manage liquidity stake");
        }
        */

        stake.stakedTokens += stakedTokens;
  
        uint256 addStakedTokens = stakeType.isLiquidity ? 0 : stakedTokens;
        uint256 addStakedLiquidityTokens = stakeType.isLiquidity ? stakedTokens : 0;
        uint256 addDividendTokens = amount * stakeType.multiplier;

        adjustDividendsETHBalance(
            stake,
            addStakedTokens,
            addStakedLiquidityTokens,
            addDividendTokens,
            true
        );
      
        if(stakeType.giveTokenDividends) {
            adjustDividendsTokenBalance(
                stake,
                0,
                0,
                addDividendTokens,
                true);
        }

        emit TokensStaked(account, key, amount, newStake, msg.sender == address(this));
    }

    function unstakeTokens(uint256 key, uint256 stakedTokens) external {
        StakeType storage stakeType = stakeTypes[key];
        require(stakeType.duration > 0 && !stakeType.isLiquidity, "Invalid stake type");

        Stake storage stake = stakes[msg.sender][key];
        require(stake.account == msg.sender, "Invalid stake");

        uint256 timeSinceStakeStart = block.timestamp - stake.startTime;

        require(timeSinceStakeStart >= stakeType.duration * 1 days, "Stake is not over");

        if(stakedTokens == 0) {
            stakedTokens = stake.stakedTokens;
        }
        else {
            require(stakedTokens <= stake.stakedTokens, "Invalid amount");
        }

        uint256 stakedTokensBefore = stake.stakedTokens;
        stake.stakedTokens -= stakedTokens;

        uint256 removeStakedTokens = stakeType.isLiquidity ? 0 : stakedTokens;
        uint256 removeStakedLiquidityTokens = stakeType.isLiquidity ? stakedTokens : 0;
        uint256 removeDividendTokensETH = stakedTokens * stake.dividendTokensETH / stakedTokensBefore;

        adjustDividendsETHBalance(
            stake,
            removeStakedTokens,
            removeStakedLiquidityTokens,
            removeDividendTokensETH,
            false);
      
        if(stakeType.giveTokenDividends) {
            uint256 removeDividendTokensToken = stakedTokens * stake.dividendTokensToken / stakedTokensBefore;

            adjustDividendsTokenBalance(
                stake,
                0,
                0,
                removeDividendTokensToken,
                false);
        }

        if(stake.stakedTokens == 0) {
            delete stakes[msg.sender][key];
        }

        if(!stakeType.isLiquidity) {
            token.transfer(msg.sender, stakedTokens);
        }
        else {
            token.pair().transfer(msg.sender, stakedTokens);
        }

        emit TokensUnstaked(msg.sender, key, stakedTokens, stake.stakedTokens == 0);
    }

    bool private inZap;

    function performZap(uint256 key, uint256 tokenAmount, uint256 amountOutMin) external payable onlyEnabled {
        require(!inZap, "Already zapping");
        require(msg.value > 0, "No money sent");
        inZap = true;

        StakeType storage stakeType = stakeTypes[key];
        require(stakeType.duration > 0, "Invalid stake type");

        if(stakeType.isLiquidity) {
            uint256 tokenBalanceStart = token.balanceOf(address(this));
            uint256 tokenBalanceBefore = tokenBalanceStart;

            //If token amount is present, it means to zap with that amount, and all the ETH
            if(tokenAmount > 0) {
                token.transferFrom(msg.sender, address(this), tokenAmount);
            }
            //If token amount is 0, it means to zap with half the ETH
            else {
                buyTokens(msg.value / 2, amountOutMin);
            }

            tokenAmount = token.balanceOf(address(this)) - tokenBalanceBefore;

            uint256 value = address(this).balance;

            uint256 pairBalanceBefore = token.pair().balanceOf(address(this));
            tokenBalanceBefore = token.balanceOf(address(this));

            token.approve(address(token.router()), type(uint256).max);

            token.router().addLiquidityETH{value: value}(
                address(token),
                tokenAmount,
                0,
                0,
                address(this),
                block.timestamp
            );

            uint256 pairBalanceGain = token.pair().balanceOf(address(this)) - pairBalanceBefore;
            uint256 tokenBalanceEnd = token.balanceOf(address(this));
            uint256 tokenBalanceLoss = tokenBalanceBefore - tokenBalanceEnd;
            
            _stakeTokens(key, pairBalanceGain, tokenBalanceLoss * 2, msg.sender);

            require(tokenBalanceEnd >= tokenBalanceStart, "Invalid balance");

            if(tokenBalanceEnd > tokenBalanceStart) {
                token.transfer(msg.sender, tokenBalanceEnd - tokenBalanceStart);
            }
        }
        else {
            require(tokenAmount == 0, "Invalid tokenAmount");
            uint256 tokenBalanceBefore = token.balanceOf(address(this));
            buyTokens(msg.value, amountOutMin);
            uint256 tokensBought = token.balanceOf(address(this)) - tokenBalanceBefore;

            _stakeTokens(key, tokensBought, tokensBought, msg.sender);
        }

        if(address(this).balance > 0) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "Error sending");
        }

        inZap = false;
    }

    function buyTokens(uint256 value, uint256 amountOutMin) private {
        address[] memory path = new address[](2);
        path[0] = address(token.router().WETH());
        path[1] = address(token);

        token.router().swapExactETHForTokensSupportingFeeOnTransferTokens{value: value}(
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
    }

    function adjustDividendsETHBalance(Stake storage stake, uint256 stakedTokens, uint256 stakedLiquidityTokens, uint256 amount, bool add) private {
        if(add) {
            accountStakedTokens[stake.account] += stakedTokens;
            accountStakedLiquidityTokens[stake.account] += stakedLiquidityTokens;
            stake.dividendTokensETH += amount;
            accountDividendTokensETH[stake.account] += amount;
            stakeTypeStakedAmount[stake.key] += stakedTokens + stakedLiquidityTokens;
        }
        else {
            accountStakedTokens[stake.account] -= stakedTokens;
            accountStakedLiquidityTokens[stake.account] -= stakedLiquidityTokens;
            stake.dividendTokensETH -= amount;
            accountDividendTokensETH[stake.account] -= amount;
            stakeTypeStakedAmount[stake.key] -= stakedTokens + stakedLiquidityTokens;
        }

        uint256 divBalance = getDividendBalance(address(token.dividendsETH()), stake.account);
        token.dividendsETH().setBalance(payable(stake.account), divBalance);
    }

    function adjustDividendsTokenBalance(Stake storage stake, uint256 stakedTokens, uint256 stakedLiquidityTokens, uint256 amount, bool add) private {
        if(add) {
            accountStakedTokens[stake.account] += stakedTokens;
            accountStakedLiquidityTokens[stake.account] += stakedLiquidityTokens;
            stake.dividendTokensToken += amount;
            accountDividendTokensToken[stake.account] += amount;
            stakeTypeStakedAmount[stake.key] += stakedTokens + stakedLiquidityTokens;
        }
        else {
            accountStakedTokens[stake.account] -= stakedTokens;
            accountStakedLiquidityTokens[stake.account] -= stakedLiquidityTokens;
            stake.dividendTokensToken -= amount;
            accountDividendTokensToken[stake.account] -= amount;
            stakeTypeStakedAmount[stake.key] -= stakedTokens + stakedLiquidityTokens;
        }

        uint256 divBalance = getDividendBalance(address(token.dividendsTokens()), stake.account);
        token.dividendsTokens().setBalance(payable(stake.account), divBalance);
    }

    function accountData(address account, uint256[] memory keys) external view returns (uint256[] memory result) {
        result = new uint256[](keys.length * 7 + 3);

        for(uint i = 0; i < keys.length; i++) {
            Stake storage stake = stakes[account][keys[i]];

            result[i * 7 + 0] = stake.startTime;
            result[i * 7 + 1] = stake.stakedTokens;
            result[i * 7 + 2] = stake.dividendTokensETH;
            result[i * 7 + 3] = stake.dividendTokensToken;

            if(token.dividendsETH().totalSupply() > 0) {
                result[i * 7 + 4] = token.dividendsETH().estimatedWeeklyDividends() * stake.dividendTokensETH / token.dividendsETH().totalSupply();
            }
            if(token.dividendsTokens().totalSupply() > 0) {
                result[i * 7 + 5] = token.dividendsTokens().estimatedWeeklyDividends() * stake.dividendTokensToken / token.dividendsTokens().totalSupply();
            }

            result[i * 7 + 6] = stakeTypeStakedAmount[keys[i]];
        }

        result[keys.length * 7] = accountStakedTokens[account];
        result[keys.length * 7 + 1] = accountStakedLiquidityTokens[account];
        result[keys.length * 7 + 2] = enabled ? 1 : 0;
    }
}
