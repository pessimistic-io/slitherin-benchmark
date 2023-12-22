// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;

import "./RamsesVaultStorage.sol";
import "./Math.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuardUpgradeable.sol";

// => Lock RAM-Tokens [votingEscrow] => veNFT => vote [Voter] => ClaimFee[Voter]
// -> withdraw -> getReward[Gauge] -> updateUserRewards -> removeLiquidity -> Transfer RAM to user

contract RamsesVault is
    RamsesVaultStorage,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    error ZERO_AMOUNT();

    event Deposit(uint256 amount0, uint256 amount1, uint256 liquidity);
    event Withdraw(
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity,
        uint256 reward
    );

    function initialize(
        address _token0,
        address _token1,
        bool _stable,
        address _feeRecipient
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        address pairToken = RAMSES_ROUTER.pairFor(_token0, _token1, _stable);
        lp = IPair(pairToken);
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        stable = _stable;
        feeRecipient = _feeRecipient;
    }

    /**
     * @dev deposit function will take amount of tokens
     * @param amount0 amount of token0
     * @param amount1 amount of token1
     * @notice be careful when you pass arguments pass amount0 according to the token0 decimals and others
     */
    function deposit(uint256 amount0, uint256 amount1) external nonReentrant {
        if (amount0 == 0 || amount1 == 0) revert ZERO_AMOUNT();
        (uint256 amountA , uint256 amountB ,uint256 liquidity) = _addLiquidity(amount0, amount1);
        Deposits memory deposit = deposits[msg.sender];
        deposit.amount0 += amountA;
        deposit.amount1 += amountB;
        deposit.liquidity += liquidity;
        deposits[msg.sender] = deposit;

        if(amount0 > amountA )token0.transfer(msg.sender, amount0.sub(amountA));
        if(amount1 > amountB )token1.transfer(msg.sender, amount1.sub(amountB));

        _deposit(liquidity);
        emit Deposit(amountA, amountB, liquidity);
    }

    /*
     * @dev This function will take LP tokens of the pool of token0-token1
     * @param liquidity is the amount of lp tokens
     */
    function depositLP(uint256 liquidity) external nonReentrant {
        if (liquidity == 0) revert ZERO_AMOUNT();
        lp.transferFrom(msg.sender, address(this), liquidity);

        Deposits memory deposit = deposits[msg.sender];
        deposit.liquidity += liquidity;
        deposits[msg.sender] = deposit;

        _deposit(liquidity);
    }

    /*
     * @dev This function will withdraw user tokens either user deposited pool tokens or pool lps
     */
    function withdraw() external nonReentrant {
        address account = msg.sender;
        Deposits memory deposit = deposits[account];
        _claimRamTokens();
        RAMSES_GAUGE.withdraw(deposit.liquidity);
        updateRewardPerToken(account);
        uint256 amount0;
        uint256 amount1;
        
        (amount0, amount1) = _removeLiquidity(account);

        uint256 _reward = storedRewardsPerUser[account];
        if (_reward > 0 && RAM_TOKEN.balanceOf(address(this)) >= _reward) {
            storedRewardsPerUser[account] = 0;
            RAM_TOKEN.transfer(
                account,
                Math.min(_reward, RAM_TOKEN.balanceOf(address(this)))
            );
        }
        derivedBalances[account] = derivedBalance(account);
        emit Withdraw(amount0, amount1, deposit.liquidity, _reward);

        delete deposits[account];
    }

    /* 
    * @dev update locking period
    */
    function setLockTime(uint256 _time) external onlyOwner {
        if (_time == 0) revert ZERO_AMOUNT();
        MAX_LOCK = _time;
    }

    function _deposit(uint256 liquidity) internal {
        lp.approve(address(RAMSES_GAUGE), liquidity);
        RAMSES_GAUGE.depositAll(tokenId);
        updateRewardPerToken(msg.sender);
        derivedBalances[msg.sender] = derivedBalance(msg.sender);
    }

    function _addLiquidity(
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 amountA, uint256 amountB,uint256 liquidity)  {
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        token0.approve(address(RAMSES_ROUTER), amount0);
        token1.approve(address(RAMSES_ROUTER), amount1);
        (amountA,amountB,liquidity) = RAMSES_ROUTER.addLiquidity(
            address(token0),
            address(token1),
            stable,
            amount0,
            amount1,
            0,
            0,
            address(this),
            block.timestamp + 600
        );
    }

    function _removeLiquidity(
        address _account
    ) internal returns (uint256 amount0, uint256 amount1) {
        Deposits memory deposit = deposits[_account];
        lp.approve(address(RAMSES_ROUTER), deposit.liquidity);

        (amount0, amount1) = RAMSES_ROUTER.removeLiquidity(
            address(token0),
            address(token1),
            stable,
            deposit.liquidity,
            0,
            0,
            _account,
            block.timestamp + 600
        );
    }

    function _claimRamTokens() internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(RAM_TOKEN);
        // claim RAM tokens
        RAMSES_GAUGE.getReward(address(this), tokens);
    }

    function updateRewardPerToken(address account) internal {
        derivedSupply = RAMSES_GAUGE.derivedSupply();
        rewardPerTokenStored = RAMSES_GAUGE.rewardPerToken(address(RAM_TOKEN));
        storedRewardsPerUser[account] = earned(account);
        userRewardPerTokenStored[account] = rewardPerTokenStored;
    }

    function derivedBalance(address account) internal view returns (uint256) {
        uint256 _balance = deposits[account].liquidity;
        uint256 _derived = (_balance * 40) / 100;
        uint256 _adjusted = 0;
        return Math.min((_derived + _adjusted), _balance);
    }

    function earned(address account) internal view returns (uint256) {
        return
            (derivedBalances[account] *
                (RAMSES_GAUGE.rewardPerToken(address(RAM_TOKEN)) -
                    userRewardPerTokenStored[account])) /
            uint256(PRECISION) +
            storedRewardsPerUser[account];
    }
}

