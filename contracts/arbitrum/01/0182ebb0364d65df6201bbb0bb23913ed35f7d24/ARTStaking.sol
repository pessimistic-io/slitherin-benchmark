//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC1155.sol";
import "./Math.sol";
import "./IERC20.sol";

import "./IERC1155Receiver.sol";
import "./IERC20.sol";
import "./EnumerableSet.sol";

struct ERC1155NFT {
  address nftAddress;
  uint8 nftID;
  uint256 reward;
  uint lastBlock;
}

contract ARTStaking is IERC1155Receiver {

  // Block when rewards will be ended
  uint public immutable rewardEndBlock;

  // Block when rewards will be started
  uint public rewardStartBlock;

  // Holds all NFTs
  ERC1155NFT[] private allNFTs;

  //keep record of the owner of NFT
  mapping(address => mapping(address => ERC1155NFT[])) private nftBank;

  // Total Rewards to be distributed
  uint256 public totalRewards;

  // duration of staking period
  uint256 public totalBlocks;

  // Reward Token Address, this contract must have reward tokens in it
  address public immutable rewardToken;

  uint256 public rewardsPerBlock;

  // rank => weight
  mapping(uint256 => uint256) public weightOfRank;
  // rank total Usage
  mapping(uint256 => uint256) public rankUsage;

  uint256 public totalUsageWithWeight = 0;

  address public immutable owner;

  using EnumerableSet for EnumerableSet.AddressSet;

  // Address of allowed NFT's
  EnumerableSet.AddressSet private allowedNfts;

  constructor(
    uint _rewardStartBlock,
    uint256 _totalRewards,
    uint _totalBlocks,
    address _rewardToken,
    address[] memory _allowedNfts
  ) {
    rewardStartBlock = _rewardStartBlock;
    totalRewards = _totalRewards;
    totalBlocks = _totalBlocks;
    rewardToken = _rewardToken;
    rewardsPerBlock = totalRewards / totalBlocks;
    rewardEndBlock = rewardStartBlock + _totalBlocks;
    owner = msg.sender;

    weightOfRank[0] = 220;
    weightOfRank[1] = 143;
    weightOfRank[2] = 143;
    weightOfRank[3] = 58;
    weightOfRank[4] = 58;
    weightOfRank[5] = 58;
    weightOfRank[6] = 9;
    weightOfRank[7] = 9;
    weightOfRank[8] = 9;
    weightOfRank[9] = 9;

    for (uint256 i = 0; i < _allowedNfts.length; i++) {
      allowedNfts.add(_allowedNfts[i]);
    }
  }

  // stake NFT,
  function stake(uint8 _nftID, address _nftAddress) external {

    require(allowedNfts.contains(_nftAddress), "only ART's are allowed");
    // require(_nftID <= 9, "upto 9 rank is allowed");

    //check if it is within the staking period
    require(rewardStartBlock <= block.number,"reward period not started yet");
    //check if it is within the staking period
    require(block.number < rewardEndBlock, "reward period has ended");
    
    //check if the owner has approved the contract to safe transfer the NFT
    require(IERC1155(_nftAddress).isApprovedForAll(msg.sender, address(this)), "approve missing");

    ERC1155NFT memory nft = ERC1155NFT({
      nftAddress: _nftAddress,
      nftID: _nftID,
      reward: 0,
      lastBlock: Math.min(block.number, rewardEndBlock)
    });

    nftBank[msg.sender][_nftAddress].push(nft);
    allNFTs.push(nft);
    // update rank
    increaseRank(_nftID);
    IERC1155(_nftAddress).safeTransferFrom(
      msg.sender,
      address(this),
      _nftID,
      1,
      "0x0"
    );
  }

  function unstake(uint8 _nftID, address _nftAddress) external {

    require(
      checkIFExists(nftBank[msg.sender][_nftAddress], _nftID),
      "token not deposited"
    );

    decreaseRank(_nftID);
    uint256 reward = _getAccumulatedrewards(_nftAddress, _nftID);

    deleteNFTFromBank(_nftAddress, msg.sender, _nftID);
    removeNFTFromArray(_nftAddress, _nftID);

    IERC20(rewardToken).transfer(msg.sender, reward);

    IERC1155(_nftAddress).safeTransferFrom(
      address(this),
      msg.sender,
      _nftID,
      1,
      "0x0"
    );    
  }

  function viewReward(uint8 _nftID, address _nftAddress)
    external
    view
    returns (uint256)
  {
    uint256 calculatedReward = 0;
    for (uint256 i = 0; i < allNFTs.length; i++) {
      if (allNFTs[i].nftID == _nftID && allNFTs[i].nftAddress == _nftAddress) {
        uint256 rewardPerShare = 0;

        if (totalUsageWithWeight > 0) {
          rewardPerShare = (rewardsPerBlock / totalUsageWithWeight);
        } else {
          rewardPerShare = rewardsPerBlock;
        }

        calculatedReward =
          allNFTs[i].reward +
          (weightOfRank[allNFTs[i].nftID] *
            rewardPerShare *
            (Math.min(block.number, rewardEndBlock) - allNFTs[i].lastBlock));
      }
    }
    return calculatedReward;
  }

  function supportsInterface(bytes4 interfaceId)
    public
    pure
    override
    returns (bool)
  {
    return
      interfaceId == type(IERC1155Receiver).interfaceId ||
      interfaceId == type(IERC20).interfaceId;
  }

  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes memory
  ) public pure override returns (bytes4) {
    return
      bytes4(
        keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")
      );
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] memory,
    uint256[] memory,
    bytes memory
  ) public pure override returns (bytes4) {
    return
      bytes4(
        keccak256(
          "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"
        )
      );
  }

  function checkIFExists(ERC1155NFT[] memory _nfts, uint8 _nftID)
    internal
    pure
    returns (bool)
  {
    for (uint8 i = 0; i < _nfts.length; i++) {
      if (_nfts[i].nftID == _nftID) {
        return true;
      }
    }
    return false;
  }

  function viewStakedNFTIds(address _owner, address _nftAddress)
    public
    view
    returns (uint8[] memory)
  {
    uint8[] memory ids = new uint8[](nftBank[_owner][_nftAddress].length);
    for (uint8 i = 0; i < nftBank[_owner][_nftAddress].length; i++) {
      ids[i] = (nftBank[_owner][_nftAddress][i].nftID);
    }
    return ids;
  }

  function viewStakedNFTs(address _owner)
    public
    view
    returns (address[] memory)
  {
    address[] memory nftTypes = new address[](15);
    for (uint8 i = 0; i < allowedNfts.length(); i++) {
      if (nftBank[_owner][allowedNfts.at(i)].length > 0) {
        nftTypes[i] = allowedNfts.at(i);
      }
    }
    return nftTypes;
  }

  function viewAllowedNFTs() public view returns (address[] memory) {
    address[] memory nftTypes = new address[](15);
    for (uint8 i = 0; i < allowedNfts.length(); i++) {
      nftTypes[i] = allowedNfts.at(i);
    }
    return nftTypes;
  }

  function deleteNFTFromBank(
    address _nftAddress,
    address _owner,
    uint8 _nftID
  ) internal {
 
    for (uint8 i = 0; i < nftBank[_owner][_nftAddress].length; i++) {
      if (nftBank[_owner][_nftAddress][i].nftID == _nftID) {
         nftBank[_owner][_nftAddress][i] = nftBank[_owner][
          _nftAddress
        ][nftBank[_owner][_nftAddress].length - 1];
        nftBank[_owner][_nftAddress].pop();
      }
    }
  }

  function calculateRewards() internal {
    for (uint8 i = 0; i < allNFTs.length; i++) {
      uint256 rewardPerShare = 0;

      if (totalUsageWithWeight > 0) {
        rewardPerShare = (rewardsPerBlock / totalUsageWithWeight);
      } else {
        rewardPerShare = rewardsPerBlock;
      }

      // reward = (weightofrank * rewardPerShare) * totalBlocks
      
      uint smallerBlock = Math.min(block.number, rewardEndBlock);
      
      allNFTs[i].reward += (weightOfRank[allNFTs[i].nftID] *
        rewardPerShare *
        (smallerBlock - allNFTs[i].lastBlock));

      allNFTs[i].lastBlock = smallerBlock;
    }
  }

  function _getAccumulatedrewards(address _nftAddress, uint8 _nftID)
    internal
    view
    returns (uint256)
  {
    uint256 reward = 0;

    for (uint8 i = 0; i < allNFTs.length; i++) {
      if (allNFTs[i].nftID == _nftID && allNFTs[i].nftAddress == _nftAddress) {
        reward = allNFTs[i].reward;
        //allNFTs[i].reward = 0;
      }
    }

    return reward;
  }

  function increaseRank(uint8 _rank) internal {
    calculateRewards();
    
    //increase this NFT's rank counter
    rankUsage[_rank] = rankUsage[_rank] + 1;
    
    //totalUsage = number of that rank used
    totalUsageWithWeight = totalUsageWithWeight + (1 * weightOfRank[_rank]);
  }

  function decreaseRank(uint8 _rank) internal {
    calculateRewards();
    rankUsage[_rank] = rankUsage[_rank] - 1;
    totalUsageWithWeight = totalUsageWithWeight - (1 * weightOfRank[_rank]);
  }

  function expectedRewardTillEnd(uint8 _nftID)
    external
    view
    returns (uint256)
  {
    uint256 rewardPerShare = 0;
    uint256 weight = 0;

    
    if (rankUsage[_nftID]<=0){
      weight = totalUsageWithWeight + weightOfRank[_nftID];
    } else{
      weight = weightOfRank[_nftID];
    }

    if (weight > 0) {
      rewardPerShare = (rewardsPerBlock / weight);
    } else {
      rewardPerShare = rewardsPerBlock;
    }
    return
      weightOfRank[_nftID] * rewardPerShare * (rewardEndBlock - block.number);
  }

  function addNFTtoArray(ERC1155NFT memory _nft) internal {
    allNFTs.push(_nft);
  }

  function removeNFTFromArray(address _nftAddress, uint8 _nftID) internal {
    for (uint8 i = 0; i < allNFTs.length; i++) {
      if (allNFTs[i].nftID == _nftID && allNFTs[i].nftAddress == _nftAddress) {
        allNFTs[i] = allNFTs[allNFTs.length - 1];
        allNFTs.pop();
      }
    }
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "only owner can do this action");
    _;
  }

  function withdrawToken(address _tokenContract, uint8 _amount)
    external
    onlyOwner
  {
    require(_tokenContract != rewardToken, "rewards token not allowed");
    IERC20 tokenContract = IERC20(_tokenContract);
    tokenContract.transfer(msg.sender, _amount);
  }

  function withdrawEth() external onlyOwner {
    payable(msg.sender).transfer(address(this).balance);
  }

  function burnRewardToken() external {
    require(rewardEndBlock < block.number, "reward period is still on");
    require(allNFTs.length == 0, "NFT's are still staked");
    IERC20 tokenContract = IERC20(rewardToken);
    tokenContract.transfer(
      address(0x000000000000000000000000000000000000dEaD),
      tokenContract.balanceOf(address(this))
    );
  }
}

