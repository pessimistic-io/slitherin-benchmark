// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./Pausable.sol";
import "./EnumerableSet.sol";
import "./EnumerableValues.sol";


contract TradeRebate is ReentrancyGuard, Ownable, Pausable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableValues for EnumerableSet.UintSet;

    bytes constant prefix = "\x19Ethereum Signed Message:\n32";
    receive() external payable {
        //require(msg.sender == weth, "invalid sender");
    }

    uint256[] private signPrefixCode;
    address public updater;
    EnumerableSet.AddressSet internal whitelistTokens;
    EnumerableSet.UintSet internal updatedRound;

    //User parts
    struct userSummaryInfo {       
        uint256 accumRound;
        mapping(address => uint256) accumRewards;

        uint256 largestClaimRound;
        EnumerableSet.UintSet claimedRound;
        // mapping(uint256 => bool) isRoundClaimed;
        // mapping(uint256 => mapping(address => uint256)) roundClaimedAmounts;
        mapping(address => uint256) totalClaimedAmounts;
    }
    mapping(address => userSummaryInfo) internal userSummaryInfos;

    struct Round {
        uint256 timeStart;
        uint256 timeStop;
        uint256 participantNum;
        uint256 volume;
        mapping(address => uint256) rewards;
    }
    mapping(uint256 => Round) private rounds;

    modifier onlyUpdater() {
        require(msg.sender == updater, "forbidden");
        _;
    }

    event ClaimRound(address _account, uint256 _roundId, address[]  _rTokens, uint256[] _rewards);
    event ClaimAccum(address _account, uint256 _roundId, address[]  _rTokens, uint256[] _rewards);
    //code for owner setting
    function setTokenState(address[] memory _tokens, bool _state) external onlyOwner {
        for(uint8 i = 0; i < _tokens.length; i++){
            if (_state && !whitelistTokens.contains(_tokens[i]))
                whitelistTokens.add(_tokens[i]);
            else if (!_state && whitelistTokens.contains(_tokens[i]))
                whitelistTokens.remove(_tokens[i]);
        }
    }
    function setSignPrefixCode(uint256[] memory _setPrefix) external onlyOwner {
        signPrefixCode = _setPrefix;
    }
    function setUpdater(address _updater) external onlyOwner{
        updater = _updater;
    }

    function withdrawToken(address _account, address _token, uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }



    function claimRound(uint256 _roundId, address[] memory _rTokens, uint256[] memory _rewards, bytes memory _updaterSignedMsg) public nonReentrant whenNotPaused {
        address _account = msg.sender;
        require(VerifyFull(signPrefixCode[1], _account, _roundId, _rTokens, _rewards, _updaterSignedMsg), "Verification Failed");
        require(_isRoundClimale(_roundId), "round not claimable");
        Round storage newRound = rounds[_roundId];
        // require(newRound.timeStart > 0 && newRound.timeStop > newRound.timeStart, "round not set");

        userSummaryInfo storage uSI = userSummaryInfos[_account];
        require(uSI.accumRound < _roundId && !uSI.claimedRound.contains(_roundId) , "already claimed");
        uSI.largestClaimRound = uSI.largestClaimRound > _roundId ? uSI.largestClaimRound : _roundId;
        uSI.claimedRound.add(_roundId);
        for(uint8 i = 0; i < _rTokens.length; i++){
            require(whitelistTokens.contains(_rTokens[i]), "not supported token");
            if (_rewards[i] < 1) 
                continue;
            require(_rewards[i] <= newRound.rewards[_rTokens[i]], "reward exceed.");
            uSI.totalClaimedAmounts[_rTokens[i]] = uSI.totalClaimedAmounts[_rTokens[i]].add(_rewards[i]);
            IERC20(_rTokens[i]).safeTransfer(_account, _rewards[i]);
        }
        emit ClaimRound(_account, _roundId, _rTokens, _rewards);
    }



    function claimAccum(uint256 _latestRound, address[] memory _rTokens, uint256[] memory _TotalRewards, bytes memory _updaterSignedMsg) public nonReentrant whenNotPaused {
        address _account = msg.sender;
        require(VerifyFull(signPrefixCode[0], _account, _latestRound, _rTokens, _TotalRewards, _updaterSignedMsg), "Verification Failed");

        userSummaryInfo storage uSI = userSummaryInfos[_account];
        require(uSI.largestClaimRound <= _latestRound, "please use latest rewards");

        uSI.largestClaimRound = _latestRound;
        uSI.accumRound = _latestRound;

        for(uint8 i = 0; i < _rTokens.length; i++){
            address _token = _rTokens[i];
            require(whitelistTokens.contains(_token), "not supported token");
            uint256 _reward = _TotalRewards[i] > uSI.totalClaimedAmounts[_token] ? _TotalRewards[i].sub(uSI.totalClaimedAmounts[_token]) : 0;
            if (_reward < 1) 
                continue;
            uSI.totalClaimedAmounts[_rTokens[i]] = uSI.totalClaimedAmounts[_rTokens[i]].add(_reward);
            IERC20(_rTokens[i]).safeTransfer(_account, _reward);
        }
        emit ClaimAccum(_account, _latestRound,  _rTokens,  _TotalRewards);
    }


    //code for public view
    function userInfo(address _account) public view returns (address[] memory, uint256[] memory){
        userSummaryInfo storage uSI = userSummaryInfos[_account];
        uint256[] memory _fullClaimedRounds = uSI.claimedRound.valuesAt(0, uSI.claimedRound.length());
        uint256 _upNum = 0;
        for(uint256 i = 0; i < _fullClaimedRounds.length; i++){
            if (_fullClaimedRounds[i] > uSI.accumRound)
                _upNum += 1;
        }

        address[] memory _tokens = getRewardTokens();
        uint256[] memory _infos = new uint256[](_tokens.length + 1 + _upNum);
        for(uint8 i = 0; i < _tokens.length; i++){
            _infos[i] = uSI.totalClaimedAmounts[_tokens[i]];
        }

        _infos[_tokens.length] = uSI.accumRound;
        uint256 _addCount = 1;
        for(uint256 i = 0; i < _fullClaimedRounds.length; i++){
            if (_fullClaimedRounds[i] > uSI.accumRound){
                _infos[_tokens.length + _addCount] = _fullClaimedRounds[i];
                _addCount = _addCount.add(1);
            }
        }
        return (_tokens, _infos);
    }


    function getRewardTokens( ) public view returns (address[] memory){
        return whitelistTokens.valuesAt(0, whitelistTokens.length());
    }

    //code for verify
    function VerifyMessage(bytes32 _hashedMessage, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, _hashedMessage));
        address signer = ecrecover(prefixedHashMessage, _v, _r, _s);
        return signer;
    }

    function splitSignature(bytes memory sig) public pure returns (bytes32 r, bytes32 s, uint8 v){
        require(sig.length == 65, "invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) public pure returns (address){
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function VerifyFull(uint256 _signPrefix, address _account, uint256 _latestRound, address[] memory _tokens, uint256[] memory _rewards, bytes memory _updaterSignedMsg) public view returns (bool) {
        require(_tokens.length > 0 && _tokens.length == _rewards.length, "invalid paras");
        bytes memory content = abi.encodePacked(_signPrefix, _account, _latestRound);
        for(uint8 i = 0; i < _tokens.length; i++){
            content =  abi.encodePacked(content, _tokens[i], _rewards[i]);
        }
        bytes32 _calHash = keccak256(content);
        bytes32 ethSignedHash = keccak256(abi.encodePacked(prefix, _calHash));
        return recoverSigner(ethSignedHash, _updaterSignedMsg) == updater;
    }


    function setRound(uint256 _roundId,  uint256 _timeStart, uint256 _timeStop, uint256 _participantNum,
            uint256 _volume, address[] memory _rewardTokens, uint256[] memory _rewardTotalAmounts) external onlyUpdater {
        require(_rewardTokens.length > 0 && _rewardTokens.length == _rewardTotalAmounts.length, "invalid setting");
        if (!updatedRound.contains(_roundId))
            updatedRound.add(_roundId);

        Round storage newRound = rounds[_roundId];
        newRound.timeStart = _timeStart;
        newRound.timeStop = _timeStop;
        newRound.participantNum = _participantNum;
        newRound.volume = _volume;

        for(uint256 i = 0; i < _rewardTokens.length; i++){
            if (!whitelistTokens.contains(_rewardTokens[i]))    
                whitelistTokens.add(_rewardTokens[i]);
            newRound.rewards[_rewardTokens[i]] = _rewardTotalAmounts[i];
        }
    }

    function deleteRound(uint256 _roundId) external onlyUpdater {
        delete rounds[_roundId];
    }

    function updatedRoundList( ) public view returns (uint256[] memory) {
        return updatedRound.valuesAt(0, updatedRound.length());
    }

    function getRoundInfo(uint256 _roundId, address _account) public view returns ( address[] memory, uint256[] memory){
        address[] memory tokenList = getRewardTokens();
        uint256[] memory info = new uint256[](tokenList.length + 6);
        Round storage _round = rounds[_roundId];
        for(uint256 i = 0; i < tokenList.length; i++ ){
            info[i] = _round.rewards[tokenList[i]];
        }
        info[tokenList.length] = _round.timeStart;
        info[tokenList.length + 1] = _round.timeStop;
        info[tokenList.length + 2] = _round.volume;
        info[tokenList.length + 3] = _round.participantNum;

        if (_account!= address(0) && _isRoundClimale(_roundId)){
            info[tokenList.length + 4] = (!userSummaryInfos[_account].claimedRound.contains(_roundId)) && userSummaryInfos[_account].accumRound < _roundId? 1 : 0;
            info[tokenList.length + 5] = (userSummaryInfos[_account].claimedRound.contains(_roundId)) || userSummaryInfos[_account].accumRound >= _roundId? 1 : 0;
        }
        
        return (tokenList, info);
    }

    function _isRoundClimale(uint256 _roundId) internal view returns (bool) {
        Round storage newRound = rounds[_roundId];
        if (newRound.timeStart < 1 || newRound.timeStop < 1)
            return false;

        if (block.timestamp < newRound.timeStop)
            return false;       

        if (newRound.participantNum < 1 || newRound.volume < 1)
            return false;
            
        return true;
    }


    //executed by updater
    // function updateRewardAll(address _account, uint256 _latestRound,  address[] memory _rTokens, uint256[] memory _rewards) public {
    //     require(msg.sender == updater, "invalid updater");
    //     _updateAllRewards(_account, _latestRound, _rTokens, _rewards);
    // }
    // function updateRewardRound(address _account, uint256 _roundId,  address[] memory _rTokens, uint256[] memory _rewards) public {
    //     require(msg.sender == updater, "invalid updater");
    //     _updateRoundRewards(_account, _roundId, _rTokens, _rewards);
    // }
    // struct userRoundInfo {
    //     uint256 timeUpdated;
    //     address[] rewardTokens;
    //     uint256[] rewardTotalAmounts;
    //     bool isClaimed;
    //     mapping(address => uint256) claimed;
    //     // uint256 tradingVolume;
    // }
    // mapping(address => mapping(uint256 => userRoundInfo)) public userRoundInfos;

}
