// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./ERC721Enumerable.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";

contract BananaPartner is Ownable, ERC721Enumerable {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.UintSet;
  uint256 private nextTokenId;
  /**
   * @dev Represents the current sales period.
   */
  uint256 public current;
  /**
   * @dev Instance of the IERC20 token contract representing the Banana token.
   */
  IERC20 public bananaToken;
  /**
   * @dev Mapping to store the blacklist status for each user.
   * The value is the status where 1 represents blacklisted and 0 represents not blacklisted.
   */
  mapping(address => uint256) private blacklist;
  /**
   * @dev Struct representing the mined information of an NFT.
   * @param periods The sales period during which the NFT was mined.
   * @param mintTime The block timestamp when the NFT was minted.
   * @param reward The reward amount associated with the NFT.
   * @param rewardDebt The pending reward debt for the NFT.
   * @param price The price paid for mining the NFT.
   */
  struct NFTInfo {
    uint256 periods;
    uint256 mintTime;
    uint256 reward;
    uint256 rewardDebt;
    uint256 price;
  }
  /**
   * @dev Struct representing a sales period.
   * It contains various properties related to the period, such as the amount,
   * mined tokens, block numbers, status, price, reward, reward debt.
   */
  struct Period {
     // The total amount of tokens in the period
    uint256 amount;          
     // The number of tokens already mined from the period
    uint256 mined;           
     // The timestamp when the period was created
    uint256 timestamp;     
     // The endTimestamp when the period ends
    uint256 endTimestamp;  
     // The status of the period (e.g., active, ended)
    uint256 status;          
     // The price of each token in the period
    uint256 price;           
     // The reward associated with the period
    uint256 reward;          
     // The debt accumulated from the reward
    uint256 rewardDebt;      
  }
  // An array of tokens associated with the period
  mapping (uint256 => EnumerableSet.UintSet) private periodsTokens;        
  /**
   * @dev Mapping to store information about each sales period.
   * The key is the period number, and the value is a struct of type Period.
   */
  mapping (uint256 => Period) public periodsInfo;
  /**
   * @dev Mapping to store NFT information for each token ID.
   * The key is the token ID, and the value is a struct of type NFTInfo.
   */
  mapping(uint256 => NFTInfo) public nftMappings;

  event Buy(address indexed sender, uint price, uint number);
  event Refund(address indexed refund, uint price, uint indexed tokenId);
  event Create(uint256 indexed period,uint256 amount, uint256 price, uint256 _timestamp, uint256 _endTimestamp);
  event Modify(uint256 indexed period,uint256 amount, uint256 price, uint256 _timestamp, uint256 _endTimestamp);
  event InjectReward(uint256 indexed period, address indexed sender, uint256 rewrd);
  event ClaimReward(address indexed sender, uint256 reward);

  constructor(IERC20 _bananaToken) ERC721("BAYC Banana Partner", "BAYCBP") {
    bananaToken = _bananaToken;
    nextTokenId = 1;
    current = 0;
  }
  modifier onlyBlacklisted() {
    require(blacklist[msg.sender] == 0, "B");
    _;
  }
  /**
   * @dev Allows a user to purchase a specified number of tokens.
   * @param number The number of tokens to purchase.
   */
  function buy(uint256 number) external payable onlyBlacklisted {
    require(number > 0 && number <= 20, "N");
    Period storage period = periodsInfo[current];
    require(period.status == 1 && period.mined < period.amount, "P");
    require(block.timestamp >= period.timestamp && block.timestamp <= period.endTimestamp, "B");
    require(msg.value >= (period.price * number), "V");
    (bool success, ) = address(this).call{value: msg.value}(new bytes(0));
    require(success, "F");
    EnumerableSet.UintSet storage tokens = periodsTokens[current];
    for (uint z = 0; z < number; z++) {
      unchecked {
        nftMappings[nextTokenId] = NFTInfo(current, block.timestamp, 0, 0, period.price);
        tokens.add(nextTokenId);
        period.mined = period.mined + 1;
        _safeMint(msg.sender, nextTokenId);
        nextTokenId++;
      }
    }
    emit Buy(msg.sender, msg.value, number);
  }
  /**
   * @dev Allows the contract owner to refund the payment made for a specific token.
   * @param tokenId The ID of the token to be refunded.
   */
  function _refund(uint256 tokenId) internal {
    Period storage period = periodsInfo[current];
    address owner = ownerOf(tokenId);
    require(period.status == 1, "P");
    NFTInfo storage nftMinedInfo = nftMappings[tokenId];
    require(owner != address(0) && nftMinedInfo.mintTime > 0, "0");
    (bool success, ) = payable(owner).call{value: nftMinedInfo.price}(new bytes(0));
    require(success, "F");
    nftMinedInfo.price = 0;
    nftMinedInfo.mintTime = 0;
    if (period.mined > 0) {
      period.mined = period.mined - 1;
    }
    emit Refund(owner, nftMinedInfo.price, tokenId);
    _burn(tokenId);
    EnumerableSet.UintSet storage tokens = periodsTokens[current];
    tokens.remove(tokenId);
    delete nftMappings[tokenId];
  }
  /**
   * @dev Allows the contract owner to refund payments made for a batch of tokens.
   * @param tokens An array of token IDs to be refunded.
   */
  function refundBatch(uint256[] memory tokens) external onlyOwner {
    for (uint i = 0; i < tokens.length; i++) {
      unchecked {
        if (tokens[i] != 0) {
          _refund(tokens[i]);
        }
      }
    }
  }
  /**
   * @dev Sets the blacklist status for a given user.
   * Only the contract owner can call this function.
   * @param _user The address of the user to be blacklisted or removed from the blacklist.
   * @param status The blacklist status to set: true for blacklisted, false for not blacklisted.
   */
  function _setBlacklist(address _user, uint256 status) internal {
    // Check if the provided user address is not zero
    require(address(0) != _user, "0");
    // Set the blacklist status for the user based on the provided status
    blacklist[_user] = status;
  }
  /**
   * @dev Sets the blacklist status for multiple users in batch.
   * Only the contract owner can call this function.
   * @param _users An array of user addresses to be blacklisted or removed from the blacklist.
   * @param status The blacklist status to set: true for blacklisted, false for not blacklisted.
   */
  function setBatchBlacklist(address[] memory _users, uint256 status) external onlyOwner {
    require(_users.length > 0 && _users.length <= 500, "0");
    // Iterate through the array of user addresses
    for (uint i = 0; i < _users.length; i++) {
      // Set the blacklist status for each user
      unchecked {
        _setBlacklist(_users[i], status);
      }
    }
  }
  /**
   * @dev Creates a new sales period.
   * @param _amount The quantity of sales.
   * @param _price The price of sales.
   * @param _timestamp The block number.
   * @param _endTimestamp The end block number.
   */
  function create(uint256 _amount, uint256 _price, uint256 _timestamp, uint256 _endTimestamp) external onlyOwner {
    // Ensures the current sales period is not already created.
    require(periodsInfo[current].status == 0, "0");
    
    // Increments the current sales period.
    current++;
    
    // Updates the sales period information.
    _update(current, _amount, _price, _timestamp, _endTimestamp);
    
    // Sets the sales period status to created.
    periodsInfo[current].status = 1;
    
    // Emits the Create event.
    emit Create(current, _amount, _price, _timestamp, _endTimestamp);
  }
  /**
   * @dev Modifies an existing sales period.
   * @param _period The sales period number.
   * @param _amount The quantity of sales.
   * @param _price The price of sales.
   * @param _timestamp The block number.
   * @param _endTimestamp The end block number.
   */
  function modify(uint256 _period, uint256 _amount, uint256 _price, uint256 _timestamp, uint256 _endTimestamp) external onlyOwner {
    // Ensures the specified sales period exists and is already created.
    require(periodsInfo[_period].status == 1, "P");
    
    // Updates the sales period information.
    _update(_period, _amount, _price, _timestamp, _endTimestamp);
    
    // Emits the Modify event.
    emit Modify(_period, _amount, _price, _timestamp, _endTimestamp);
  }
  /**
   * @dev Updates the sales period information.
   * @param _period The sales period number.
   * @param _amount The quantity of sales.
   * @param _price The price of sales.
   * @param _timestamp The block number.
   * @param _endTimestamp The end block number.
   */
  function _update(uint256 _period, uint256 _amount, uint256 _price, uint256 _timestamp, uint256 _endTimestamp) internal {
    // Ensures the sales amount does not exceed the limit.
    require(_amount <= 500, "L");
    // Retrieves the reference to the sales period struct.
    Period storage period = periodsInfo[_period];
    // Updates the sales period information.
    period.amount = _amount;
    period.price = _price;
    period.timestamp = _timestamp;
    period.endTimestamp = _endTimestamp;
  }
  /**
   * @dev Ends the current sales period.
   * Only the contract owner can call this function.
   * The sales period will be marked as ended if the following conditions are met:
   * 1. The sales period is not in an uninitialized state (status is not 0).
   * 2. The current block number is greater than or equal to the specified end block number of the period.
   */
  function ending() external onlyOwner {
    // Check if the sales period is not in an uninitialized state
    require(periodsInfo[current].status != 0, "0");
    // Mark the sales period as ended by setting its status to 0
    periodsInfo[current].status = 0;
  }
  /**
   * @dev Injects reward tokens into the contract.
   * @param _reward The amount of reward tokens to be injected.
   */
  function injectReward(uint256 _reward) external {
    require(_reward > 0 && bananaToken.balanceOf(msg.sender) >= _reward, "0");
    Period storage period = periodsInfo[current];
    require(period.status == 1 && period.mined > 0, "P");
    require(block.timestamp >= period.timestamp && block.timestamp <= period.endTimestamp, "B");
    // Transfer reward tokens from the sender to the contract
    bananaToken.safeTransferFrom(msg.sender, address(this), _reward);
    // Update the total reward for the current sales period
    period.reward = period.reward + _reward;
    // Get the token IDs for the current sales period
    EnumerableSet.UintSet storage tokens = periodsTokens[current];
    uint256 tokensLength = tokens.length();
    // Calculate the reward per share to be distributed among the token holders
    uint256 rewardAccTokenPerShare = _reward / tokensLength;
    // Distribute the reward to each token holder
    for (uint i = 0; i < tokensLength; i++) {
      unchecked {
        NFTInfo storage nftMinedInfo = nftMappings[tokens.at(i)];
        // Check if the NFT has been minted (not burned)
        if (nftMinedInfo.mintTime != 0) {
          nftMinedInfo.reward = nftMinedInfo.reward + rewardAccTokenPerShare;
        }
      }
    }
    emit InjectReward(current, msg.sender, _reward);
  }
  /**
   * @dev Clears the stuck balance by transferring the remaining tokens to the contract owner.
   * Only the contract owner can call this function.
   */
  function clearStuckBalance() external onlyOwner {
    // Transfer the remaining tokens to the contract owner
    bananaToken.transfer(_msgSender(), bananaToken.balanceOf(address(this)));
  }
  /**
   * @dev Allows the contract owner to clearStuckEthBalance the proceeds from sales.
   * The contract's balance will be transferred to the owner's address.
   * Only the contract owner can call this function.
   */
  function clearStuckEthBalance() external onlyOwner {
    // Transfer the contract's balance to the owner's address
    payable(msg.sender).call{value: address(this).balance}(new bytes(0));
  }
  /**
   * @dev Calculates the pending reward for a given user and their token IDs.
   * @param _user The address of the user.
   * @param _tokenIds An array of token IDs.
   * @return _reward The pending reward for the user.
   */
  function pendingReward(address _user, uint256[] memory _tokenIds) external view returns (uint256 _reward) {
    // Check if the user is not blacklisted
      // Return 0 if the user's balance is 0
    if (_tokenIds.length <= 0) return 0;
    if (balanceOf(_user) <= 0) return 0;
    for (uint i = 0; i < _tokenIds.length; i++) {
      unchecked {
        NFTInfo memory nftMinedInfo = nftMappings[_tokenIds[i]];
        if (nftMinedInfo.mintTime != 0) {
          if (ownerOf(_tokenIds[i]) == _user) {
            // Calculate the pending reward for the user
            _reward = _reward + nftMinedInfo.reward - nftMinedInfo.rewardDebt;
          }
        }
      }
    }
  }
  /**
   * @dev Allows a user to claim their pending reward for a given array of token IDs.
   * @param _tokenIds An array of token IDs for which the user wants to claim the reward.
   */
  function claimReward(uint256[] memory _tokenIds) external onlyBlacklisted {
    // Return 0 if the _tokenids length is 0
    if(_tokenIds.length <= 0) return;
    // Check if the user's balance is 0, and return if true
    if (balanceOf(msg.sender) <= 0) return;
    // Check if the user is not blacklisted
    uint256 _reward; // Accumulator for the pending reward
    for (uint i = 0; i < _tokenIds.length; i++) {
      unchecked {
        uint256 _tokenId = _tokenIds[i];
        NFTInfo storage nftMinedInfo = nftMappings[_tokenId];
        if (nftMinedInfo.mintTime != 0) {
          if (ownerOf(_tokenId) == msg.sender) {
            // Calculate the pending reward for the user and update the reward debt
            _reward = _reward + nftMinedInfo.reward - nftMinedInfo.rewardDebt;
            nftMinedInfo.rewardDebt = nftMinedInfo.reward;
          }
        }
      }
    }
    // If the pending reward is 0 or negative, return
    if (_reward <= 0) {
      return;
    }
    // Update the reward debt for the current sales period
    periodsInfo[current].rewardDebt = periodsInfo[current].rewardDebt + _reward;
    // Transfer the reward tokens to the user
    bananaToken.safeTransfer(msg.sender, _reward);
    // Emit the ClaimReward event
    emit ClaimReward(msg.sender, _reward);
  }
  receive() external payable {}
}

