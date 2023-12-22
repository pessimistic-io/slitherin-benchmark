// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./ITradeStorage.sol";



contract TradeRebateV2 is ReentrancyGuard, Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public rewardToken;
    address public tradeRecord;

    mapping (uint256 => uint256) public roundRewards;

    mapping (address => mapping(uint256 => uint256)) public userRoundClaimed;

    event ClaimRound(address _account, uint256 _roundId, address  _rewardToken, uint256 _rewards);
    event SetRound(uint256[] rounds, uint256[] rewards);

    function withdrawToken(address _account, address _token, uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }

    function setAddress(address _rewardToken, address _tradeRecord) external onlyOwner{
        rewardToken = _rewardToken;
        tradeRecord = _tradeRecord;
    }

    function setRound(uint256[] memory _rounds, uint256[] memory _rewards) external onlyOwner {
        for(uint256 i = 0; i < _rounds.length; i++){
            roundRewards[_rounds[i]] = _rewards[i];
        }
        emit SetRound(_rounds, _rewards);
    }

    function curRound() public view returns (uint256){
        return block.timestamp.div(86400);
    }

    function claimable(address _account, uint256 _roundId) public view returns (uint256){
        if (roundRewards[_roundId] == 0)
            return 0;

        uint256 totalVol = ITradeStorage(tradeRecord).totalTradeVol(_roundId).add(ITradeStorage(tradeRecord).totalSwapVol(_roundId));
        if (totalVol == 0)
            return 0;

        uint256 userVol = ITradeStorage(tradeRecord).tradeVol(_account, _roundId);
        userVol = userVol.add(ITradeStorage(tradeRecord).swapVol(_account, _roundId));
        uint256 _userRewd = roundRewards[_roundId].mul(userVol).div(totalVol);
        return _userRewd > userRoundClaimed[_account][_roundId] ? _userRewd.sub(userRoundClaimed[_account][_roundId]) : 0;
    }

    function claimRound(uint256 _roundId) public returns (uint256){
        uint256 _lRound = block.timestamp.div(86400);
        require(_roundId < _lRound, "Round not finished.");
        address _account = msg.sender;
        uint256 claimableRew = claimable(_account, _roundId);
        if (claimableRew < 1)
            return 0;
        require(IERC20(rewardToken).balanceOf(address(this)) > claimableRew, "insufficient reward token");

        userRoundClaimed[_account][_roundId] = userRoundClaimed[_account][_roundId].add(claimableRew);
        IERC20(rewardToken).safeTransfer(_account, claimableRew);
        emit ClaimRound(_account, _roundId, rewardToken, claimableRew);
        return claimableRew;
    }
}
