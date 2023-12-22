// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";


contract EDEtAirdrop is Ownable{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event Claimed(address claimant, uint256 round, uint256 roundClaimed, uint256 totalReward);
    event TrancheAdded(uint256 tranche, bytes32 merkleRoot, uint256 totalAmount);
    event TrancheExpired(uint256 tranche);

    IERC20 public token;
    address public updater;

    uint256 public maxClaimedPerDay;

    uint256 public latestRound;
    mapping(uint256 => uint256) public dayClaimed;
    mapping(uint256 => bytes32) public merkleRoots;
    mapping(address => uint256) public userClaimed;
    mapping(uint256 => mapping(address => bool)) public claimed;

    constructor(IERC20 _token) {
        token = _token;
    }

    function setUpdater(address _updater) public onlyOwner{
        updater = _updater;
    }

    function setMaxClaimedPerDay(uint256 _amount) public onlyOwner{
        maxClaimedPerDay = _amount;
    }
    
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }
    
    function curRound() public view returns (uint256){
        return block.timestamp.div(86400);
    }
    
    function seedNewAllocations(
            bytes32 _merkleRoot, 
            uint256 _totalRewards
            ) public {
        require(msg.sender == owner() || msg.sender == updater, "only updater");
        latestRound = curRound()-1;
        require(merkleRoots[latestRound] == bytes32(0), "round alread set");
        merkleRoots[latestRound] = _merkleRoot;
        emit TrancheAdded(latestRound, _merkleRoot, _totalRewards);
    }

    function expireTranche(uint256 _roundId) public onlyOwner{
        merkleRoots[_roundId] = bytes32(0);
        emit TrancheExpired(_roundId);
    }
    
    function claimRound(
            address _account, 
            uint256 _roundId, 
            uint256 _reward, 
            bytes32[] memory _merkleProof) public {
        _claimRound(_account, _roundId, _reward, _merkleProof);
    }

    function verifyClaim(address _account, uint256 _roundId, uint256 _balance, bytes32[] memory _merkleProof)public view returns (bool valid){
        return _verifyClaim(_account, _roundId, _balance, _merkleProof);
    }

    function _claimRound(
            address _account,
            uint256 _roundId,
            uint256 _reward,
            bytes32[] memory _merkleProof) private {
        require(merkleRoots[_roundId]!= bytes32(0), "Round not set");
        require(!claimed[_roundId][_account], "Round already claimed");
        require(_roundId == latestRound, "round not claimable");
        require(_verifyClaim(_account, _roundId, _reward, _merkleProof), "Incorrect merkle proof");
        require(userClaimed[_account] < _reward, "No rewards to claim");
        claimed[_roundId][_account] = true;
        uint256 claimAmount = _reward.sub(userClaimed[_account]);
        userClaimed[_account] = _reward;
        token.safeTransfer(_account, claimAmount);

        uint256 _day = block.timestamp / 86400;
        dayClaimed[_day] = dayClaimed[_day].add(claimAmount);
        require(dayClaimed[_day] < maxClaimedPerDay, "Daily claimable quota limited.");
        emit Claimed(_account, _roundId, claimAmount, _reward);
    }

    function _verifyClaim(
            address _account,
            uint256 _roundId,
            uint256 _reward,
            bytes32[] memory _merkleProof) private view returns (bool){
        bytes32 leaf = keccak256(abi.encodePacked(_roundId, _account, _reward));
        return MerkleProof.verify(_merkleProof, merkleRoots[_roundId], leaf);
    }

    function getLeaf(uint256 _roundId, address _account, uint256 _reward) public pure returns (bytes32){
        return keccak256(abi.encodePacked(_roundId, _account, _reward));
    }

    function getVerify(bytes32[] memory _merkleProof, bytes32 _root, bytes32 _leaf) public pure returns (bool){
        return MerkleProof.verify(_merkleProof, _root, _leaf);
    }

}
