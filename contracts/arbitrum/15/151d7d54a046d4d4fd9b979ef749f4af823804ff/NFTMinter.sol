// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./IDIPXGenesisPass.sol";
import "./TransferHelper.sol";
import "./EnumerableSet.sol";
import "./IERC20.sol";

contract NFTMinter is Ownable{
  using EnumerableSet for EnumerableSet.UintSet;

  address public dgp;
  address public feeTo;
  mapping(address => bool) public isPayToken;
  mapping(address => uint256) public prices;
  mapping(address => uint256) public priceIncrs;
  
  mapping(address => bool) public isWhitelist;
  mapping(address => bool) public isWhitelistMinted;

  uint256 public mintedNum;
  EnumerableSet.UintSet private tokenIds;
  EnumerableSet.UintSet private tokenIdMinted;

  bool public paused;

  event Mint(uint256 tokenId, address to, address payToken, uint256 price);

  constructor(address _dgp,address _feeTo, address[] memory _tokens, uint256[] memory _prices, uint256[] memory _incrs){
    require(_tokens.length == _prices.length);
    dgp = _dgp;
    feeTo = _feeTo;
    mintedNum = 0;
    for (uint256 i = 0; i < _tokens.length; i++) {
      isPayToken[_tokens[i]] = true;
      prices[_tokens[i]] = _prices[i];
      priceIncrs[_tokens[i]] = _incrs[i];
    }
  }

  function togglePaused() public onlyOwner{
    paused = !paused;
  }

  function setFeeTo(address _feeTo) public onlyOwner{
    feeTo = _feeTo;
  }

  function addWhitelist(address[] memory _accounts) public onlyOwner{
    for (uint256 i = 0; i < _accounts.length; i++) {
      isWhitelist[_accounts[i]] = true;
    }
  }

  function removeWhitelist(address[] memory _accounts) public onlyOwner{
    for (uint256 i = 0; i < _accounts.length; i++) {
      isWhitelist[_accounts[i]] = false;
    }
  }

  function addTokenId(uint256 _begin,uint256 _end) public onlyOwner{
    for (uint256 i = _begin; i < _end; i++) {
      require(!tokenIdMinted.contains(i), "token already minted");
      tokenIds.add(i);
    }
  }
  function setPayToken(address _token,bool _active,uint256 _price,uint256 _incr) external onlyOwner{
    isPayToken[_token] = _active;
    prices[_token] = _price;
    priceIncrs[_token] = _incr;
  }

  function tokenIdValues() public view returns(uint256[] memory){
    return tokenIds.values();
  }

  function tokenMintedIdValues() public view returns(uint256[] memory){
    return tokenIdMinted.values();
  }

  function _random() private view returns(uint256){
    return uint256(keccak256(abi.encodePacked(block.difficulty,blockhash(block.number-1),block.timestamp, tokenIds.length())));
  }

  function mintByWhitelist(address _to) public returns(uint256){
    require(!paused, "Mint paused");
    require(isWhitelist[msg.sender], "Not in whitelist");
    require(!isWhitelistMinted[msg.sender], "Minted");
    
    uint256 randomIndex = _random() % tokenIds.length();
    uint256 tokenId = tokenIds.values()[randomIndex];
    tokenIds.remove(tokenId);
    tokenIdMinted.add(tokenId);
    IDIPXGenesisPass(dgp).safeMint(_to,tokenId);
    mintedNum = mintedNum + 1;

    isWhitelistMinted[msg.sender] = true;

    emit Mint(tokenId,_to, address(0), 0);

    return tokenId;
  }
  function mint(address _payToken, uint256 _num, address _to) public returns(uint256[] memory){
    require(!paused, "Mint paused");
    require(isPayToken[_payToken], "Invalid token");
    require(_num <= 10 && tokenIds.length()>=_num, "Mint too many");

    uint256[] memory mintTokenIds = new uint256[](_num);
    for (uint256 i = 0; i < _num; i++) {
      uint256 price = prices[_payToken] + priceIncrs[_payToken]*mintedNum;
      IERC20(_payToken).transferFrom(msg.sender, feeTo, price);
      
      uint256 randomIndex = _random() % tokenIds.length();
      uint256 tokenId = tokenIds.values()[randomIndex];
      tokenIds.remove(tokenId);
      tokenIdMinted.add(tokenId);
      IDIPXGenesisPass(dgp).safeMint(_to,tokenId);
      mintedNum = mintedNum + 1;
      mintTokenIds[i] = tokenId;

      emit Mint(tokenId,_to, _payToken, price);
    }

    return mintTokenIds;
  }
}
