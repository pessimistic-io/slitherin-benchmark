// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IChefIncentivesController.sol";

/**
 * @title   GlpRewardsDistribution
 * @author  Maneki.finance
 * @notice  Used to distribute Maneki protocol claimed weth rewards to Glp AToken holders
 *          Based on MultiFeeDistribution:
 *          https://github.com/geist-finance/geist-protocol/blob/main/contracts/staking/MultiFeeDistribution.sol
 *          Functions as OnwardsIncentivesController of GlpAToken on ChefIncentivesController
 */

contract GlpRewardsDistribution is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STRUCTS ========== */

    struct Reward {
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 balance;
    }

    struct Balances {
        uint256 total;
        uint256 earned;
    }

    event GlpATokenUpdated(
        address user,
        uint256 userBalance,
        uint256 totalBalance
    );

    event RewardClaimed(address user, address rewardToken, uint256 amount);

    event Recovered(address savedToken, uint256 amount);

    event RewardNotifed(address rewardToken, uint256 newUnseenAmount);

    /* ========== STATE VARIABLES ========== */

    /* Address of ChefIncentivesController */
    address chefIncentivesController;

    /* Address of Glp AToken*/
    IERC20 glpAToken;

    /* Array of rewards, currently only weth */
    address[] public rewardTokens;

    /* Data of specific reward */
    mapping(address => Reward) public rewardData;

    /* Private mappings for balance data */
    mapping(address => Balances) private balances;

    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public rewards;

    uint256 totalGlpAToken;

    /* Duration that rewards will stream over */
    uint256 public constant rewardsDuration = 86400; // 1 Day

    /* ========== CONSTRUCTOR ========== */

    constructor(address _chefIncentivesController) Ownable() {
        chefIncentivesController = _chefIncentivesController;
    }

    function start(address _glpAToken, address _weth) external onlyOwner {
        glpAToken = IERC20(_glpAToken);
        rewardTokens.push(_weth);
        totalGlpAToken = glpAToken.totalSupply();
        rewardData[_weth].lastUpdateTime = block.timestamp;
        rewardData[_weth].periodFinish = block.timestamp;
    }

    function handleAction(
        address _callingToken,
        address _user,
        uint256 _userBalance,
        uint256 _totalSupply
    ) external {
        require(
            msg.sender == chefIncentivesController,
            "GlpRewardsDistribution: Only ChefIncentivesController can call"
        );
        require(
            _callingToken == address(glpAToken),
            "GlpRewardsDistribution: Invalid token"
        );
        _updateReward(_user);
        _checkUnseenAndNotify();
        totalGlpAToken = _totalSupply;
        Balances storage bal = balances[_user];
        bal.total = _userBalance;

        emit GlpATokenUpdated(_user, _userBalance, _totalSupply);
    }

    /* Claim all pending staking rewards */
    function getReward(address[] memory _rewardTokens) public {
        _updateReward(msg.sender);
        _getReward(_rewardTokens);
    }

    function addReward(address _rewardsToken) external onlyOwner {
        require(rewardData[_rewardsToken].lastUpdateTime == 0);
        rewardTokens.push(_rewardsToken);
        rewardData[_rewardsToken].lastUpdateTime = block.timestamp;
        rewardData[_rewardsToken].periodFinish = block.timestamp;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _getReward(address[] memory _rewardTokens) internal {
        uint256 length = _rewardTokens.length;
        for (uint i; i < length; i++) {
            address token = _rewardTokens[i];
            uint256 reward = rewards[msg.sender][token].div(1e12);
            Reward storage r = rewardData[token];
            uint256 periodFinish = r.periodFinish;
            require(periodFinish > 0, "Unknown reward token");
            uint256 balance = r.balance;
            if (periodFinish < block.timestamp.add(rewardsDuration - 3600)) {
                uint256 unseen = IERC20(token).balanceOf(address(this)).sub(
                    balance
                );
                if (unseen > 0) {
                    _notifyReward(token, unseen);
                    balance = balance.add(unseen);
                }
            }
            r.balance = balance.sub(reward);
            if (reward == 0) continue;
            rewards[msg.sender][token] = 0;
            IERC20(token).safeTransfer(msg.sender, reward);
            emit RewardClaimed(msg.sender, token, reward);
        }
    }

    function _checkUnseenAndNotify() internal {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            Reward storage r = rewardData[token];
            uint256 periodFinish = r.periodFinish;
            require(periodFinish > 0, "Unknown reward token");
            uint256 balance = r.balance;
            if (periodFinish < block.timestamp.add(rewardsDuration - 3600)) {
                uint256 unseen = IERC20(token).balanceOf(address(this)).sub(
                    balance
                );
                if (unseen > 0) {
                    _notifyReward(token, unseen);
                    balance = balance.add(unseen);
                }
            }
            r.balance = balance;
        }
    }

    function _notifyReward(address _rewardsToken, uint256 reward) internal {
        Reward storage r = rewardData[_rewardsToken];
        if (block.timestamp >= r.periodFinish) {
            r.rewardRate = reward.mul(1e12).div(rewardsDuration);
        } else {
            uint256 remaining = r.periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(r.rewardRate).div(1e12);
            r.rewardRate = reward.add(leftover).mul(1e12).div(rewardsDuration);
        }

        r.lastUpdateTime = block.timestamp;
        r.periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardNotifed(_rewardsToken, reward);
    }

    function _updateReward(address _account) internal {
        address token = address(glpAToken);
        uint256 balance;
        Reward storage r;
        uint256 rpt;
        uint256 supply = glpAToken.totalSupply();
        for (uint i = 0; i < rewardTokens.length; i++) {
            token = rewardTokens[i];
            r = rewardData[token];
            rpt = _rewardPerToken(token, supply);
            r.rewardPerTokenStored = rpt;
            r.lastUpdateTime = lastTimeRewardApplicable(token);
            if (_account != address(this)) {
                rewards[_account][token] = _earned(
                    _account,
                    token,
                    balance,
                    rpt
                );
                userRewardPerTokenPaid[_account][token] = rpt;
            }
        }
    }

    function _rewardPerToken(
        address _rewardsToken,
        uint256 _supply
    ) internal view returns (uint256) {
        if (_supply == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }
        return
            rewardData[_rewardsToken].rewardPerTokenStored.add(
                lastTimeRewardApplicable(_rewardsToken)
                    .sub(rewardData[_rewardsToken].lastUpdateTime)
                    .mul(rewardData[_rewardsToken].rewardRate)
                    .mul(1e18)
                    .div(_supply)
            );
    }

    function lastTimeRewardApplicable(
        address _rewardsToken
    ) public view returns (uint256) {
        uint periodFinish = rewardData[_rewardsToken].periodFinish;
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function _earned(
        address _user,
        address _rewardsToken,
        uint256 _balance,
        uint256 _currentRewardPerToken
    ) internal view returns (uint256) {
        return
            _balance
                .mul(
                    _currentRewardPerToken.sub(
                        userRewardPerTokenPaid[_user][_rewardsToken]
                    )
                )
                .div(1e18)
                .add(rewards[_user][_rewardsToken]);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /* Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders */
    function recoverERC20(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyOwner {
        require(
            rewardData[tokenAddress].lastUpdateTime == 0,
            "Cannot withdraw reward token"
        );
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /**
     * @notice  Allows the owner to recover any ether instead of weth accidentally sent to
     *          the contract.
     */
    function recoverETH(
        address payable recipient,
        uint256 amount
    ) external onlyOwner {
        require(address(this).balance != amount, "No missent ether.");
        require(
            address(this).balance >= amount,
            "Not enough Ether available in contract."
        );
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer of Ether failed.");
        emit EtherRecovered(recipient, amount);
    }

    event EtherRecovered(address indexed recipient, uint256 amount);
}

