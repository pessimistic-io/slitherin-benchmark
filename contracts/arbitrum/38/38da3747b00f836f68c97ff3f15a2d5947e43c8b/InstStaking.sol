// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";


contract InstStaking is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct RewardInfo {
        address token;
        uint256 balance;
        uint256 cumulatedRewardPerToken_PREC;
    }

    uint256 public totalSupply;
    mapping (address => RewardInfo) rewardInfo;

    address public depositToken;
    address[] public rewardTokens;

    uint256 public constant REWARD_PRECISION = 10 ** 20;
   
    //record for accounts
    mapping(address => uint256) public balance;
    mapping(address => mapping(address => uint256)) public entryCumulatedReward_PREC;
    mapping(address => mapping(address => uint256)) public unclaimedReward;
    mapping(address => mapping(uint256 => uint256)) public rewardRecord;
    constructor(address _depositToken) {
        depositToken = _depositToken;
    }

    //-- public view func.
    function balanceOf(address _account) public view returns (uint256) {
        return balance[_account];
    }

    function getRewardInfo(address _token) public view returns (RewardInfo memory){
        return rewardInfo[_token];
    }

    function getRewardTokens() public view returns (address[] memory) {
        return rewardTokens;
    }

    function pendingReward(address _token) public view returns (uint256) {
        uint256 currentBalance = IERC20(_token).balanceOf(address(this));
        return currentBalance > rewardInfo[_token].balance ? currentBalance.sub(rewardInfo[_token].balance) : 0;
    }

    function claimable(address _account) public view returns (address[] memory, uint256[] memory){
        uint256[] memory claimable_list = new uint256[](rewardTokens.length);
        for(uint8 i = 0; i < rewardTokens.length; i++){
            address _tk = rewardTokens[i];
            claimable_list[i] = unclaimedReward[_account][_tk];
            if (balance[_account] > 0 && totalSupply > 0){
                uint256 pending_reward = pendingReward(_tk);
                claimable_list[i] = claimable_list[i]
                    .add(balance[_account].mul(pending_reward).div(totalSupply))
                    .add(balance[_account].mul(rewardInfo[_tk].cumulatedRewardPerToken_PREC.sub(entryCumulatedReward_PREC[_account][_tk])).div(REWARD_PRECISION));
            }
        }
        return (rewardTokens, claimable_list);
    }

    //-- owner 
    function setRewards(address[] memory _rewardTokens) external onlyOwner {
        rewardTokens = _rewardTokens;
    }

    function withdrawToken(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function aprRecord(address _token) public view returns (uint256, uint256) {
        uint256 total_reward = 0;
        uint256 currentBalance = IERC20(_token).balanceOf(address(this));
        if (currentBalance > rewardInfo[_token].balance) 
            total_reward = currentBalance.sub(rewardInfo[_token].balance);   
        uint256 _cur_hour =  block.timestamp.div(3600);
        for(uint i = 0; i < 24; i++){
            total_reward = total_reward.add(rewardRecord[_token][_cur_hour-i]);
        }
        return (total_reward, totalSupply);
    }

    function _distributeReward(address _token) private {
        uint256 currentBalance = IERC20(_token).balanceOf(address(this));
        if (totalSupply < 1 || currentBalance <= rewardInfo[_token].balance) 
            return;

        uint256 rewardToDistribute = currentBalance.sub(rewardInfo[_token].balance);
        uint256 _hour = block.timestamp.div(3600);
        rewardRecord[_token][_hour] = rewardRecord[_token][_hour].add(rewardToDistribute);
        // calculate cumulated reward
        rewardInfo[_token].cumulatedRewardPerToken_PREC = 
            rewardInfo[_token].cumulatedRewardPerToken_PREC.add(rewardToDistribute.mul(REWARD_PRECISION).div(totalSupply));
        //update balance
        rewardInfo[_token].balance = currentBalance;
    }


    function _transferOut(address _receiver, address _token, uint256 _amount) private {
        if (_amount == 0) return;
        require(rewardInfo[_token].balance >= _amount, "[InstStaking] Insufficient token balance");
        rewardInfo[_token].balance = rewardInfo[_token].balance.sub(_amount);
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    function stake(uint256 _amount) public {
        address _account = msg.sender;
        updateRewards(_account);    
        IERC20(depositToken).safeTransferFrom(_account, address(this), _amount);
        balance[_account] = balance[_account].add(_amount);
        totalSupply = totalSupply.add(_amount);
    }   
    
    
    function unstake(uint256 _amount) public returns (address[] memory, uint256[] memory ) {
        address _account = msg.sender;
        require(balance[_account] >= _amount, "insufficient balance");
        uint256[] memory claim_res = _claim(_account);
        balance[_account] = balance[_account].sub(_amount);
        IERC20(depositToken).safeTransfer(_account, _amount);
        totalSupply = totalSupply.sub(_amount);
        return (rewardTokens, claim_res);
    }

    function claim() public returns (address[] memory, uint256[] memory ) {
        return (rewardTokens, _claim(msg.sender));
    }

    function claimForAccount(address _account) public returns (address[] memory, uint256[] memory){
        return (rewardTokens, _claim(_account));
    }

    function _claim(address _account) private returns (uint256[] memory ) {
        uint256[] memory claim_res = new uint256[](rewardTokens.length);
        updateRewards(_account);    
        for(uint8 i = 0; i < rewardTokens.length; i++){
            _transferOut(_account,rewardTokens[i], unclaimedReward[_account][rewardTokens[i]]);
            claim_res[i] = unclaimedReward[_account][rewardTokens[i]] ;
            unclaimedReward[_account][rewardTokens[i]] = 0;
        }
        return claim_res;
    }




    
    function updateRewards(address _account) public {
        for(uint8 i = 0; i < rewardTokens.length; i++){
            _distributeReward(rewardTokens[i]);
        }
        if (_account != address(0)){
            if (balance[_account] > 0){
                for(uint8 i = 0; i < rewardTokens.length; i++){
                    unclaimedReward[_account][rewardTokens[i]] = unclaimedReward[_account][rewardTokens[i]].add(
                        balance[_account].mul(rewardInfo[rewardTokens[i]].cumulatedRewardPerToken_PREC.sub(entryCumulatedReward_PREC[_account][rewardTokens[i]])).div(REWARD_PRECISION)
                        );
                }
            }
            
            for(uint8 i = 0; i < rewardTokens.length; i++){
                entryCumulatedReward_PREC[_account][rewardTokens[i]] = rewardInfo[rewardTokens[i]].cumulatedRewardPerToken_PREC;
            }
        }
    }
}

