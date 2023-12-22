// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ECDSA.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./TransferHelper.sol";
import "./IDIPXGenesisPass.sol";

contract Airdrop is Initializable,OwnableUpgradeable{
  using ECDSA for bytes32;

  address public token;
  address public genesisPass;
  address public cSigner;
  mapping(address => bool) public isClaimed;
  mapping(uint256 => bool) public isGpClaimed;
  uint256 public gpAirdrop;
  uint256 public deadline;

  event Claim(address account, uint256 value);

  function initialize(address _signer, address _token, address _genesisPass, uint256 _gpAirdrop, uint256 _deadline) public initializer{
    __Ownable_init();
    cSigner = _signer;
    token = _token;
    genesisPass = _genesisPass;
    gpAirdrop = _gpAirdrop;
    deadline = _deadline;
  }

  function setSigner(address _signer) external onlyOwner{
    cSigner = _signer;
  }
  function setDeadline(uint256 _deadline) external onlyOwner{
    deadline = _deadline;
  }

  function withdraw(address to, uint256 value) external onlyOwner{
    TransferHelper.safeTransfer(token, to, value);
  }

  function calculateGpAirdrop(address owner) public view returns(uint256){
    uint256[] memory tokenIds = IDIPXGenesisPass(genesisPass).tokenOfOwner(owner);
    uint256 amount = 0;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      uint256 a = tokenId/1000;
      uint256 b = (tokenId/100)%10;
      uint256 c = (tokenId/10)%10;
      uint256 d = tokenId%10;
      if(!isGpClaimed[tokenId]){
        if(tokenId == 0){
          amount += gpAirdrop * 100;  
        }else if(a == b && a == c && a == d){
          amount += gpAirdrop * 10;
        }else{
          amount += gpAirdrop;
        }
      }
    }

    return amount;
  }

  function claim(
    bytes memory signature, 
    uint256 gmxAirdrop,
    uint256 glpAirdrop,
    uint256 gnsAirdrop,
    uint256 testAirdrop,
    uint256 reportAirdrop,
    uint256 bountyAirdrop
  ) external {
    require(block.timestamp < deadline, "Airdrop: closed");
    require(verify(signature,gmxAirdrop,glpAirdrop,gnsAirdrop,testAirdrop,reportAirdrop,bountyAirdrop,msg.sender,cSigner), "Airdrop: Invalid signature");
    require(!isClaimed[msg.sender], "Airdrop: Claimed");

    uint256 balance = IERC20(token).balanceOf(address(this));
    uint256 holderAirdrop = gmxAirdrop + glpAirdrop + gnsAirdrop;
    uint256 maxHolderAirdropValue = 500000 * (10**IERC20Metadata(token).decimals());
    if(holderAirdrop > maxHolderAirdropValue){
      holderAirdrop = maxHolderAirdropValue;
    }
    uint256 amount = holderAirdrop + testAirdrop + reportAirdrop + bountyAirdrop + calculateGpAirdrop(msg.sender);
    if(amount > balance){
      amount = balance;
    }
    
    if(amount > 0){
      TransferHelper.safeTransfer(token, msg.sender, amount);
    }

    uint256[] memory tokenIds = IDIPXGenesisPass(genesisPass).tokenOfOwner(msg.sender);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      isGpClaimed[tokenIds[i]] = true;
    }
    isClaimed[msg.sender] = true;

    emit Claim(msg.sender, amount);
  }

  function verify(
    bytes memory signature, 
    uint256 gmxAirdrop,
    uint256 glpAirdrop,
    uint256 gnsAirdrop,
    uint256 testAirdrop,
    uint256 reportAirdrop,
    uint256 bountyAirdrop,
    address _sender, 
    address _signer
  ) public pure returns (bool) {
    bytes32 messageHash = keccak256(abi.encodePacked(_sender, gmxAirdrop,glpAirdrop,gnsAirdrop,testAirdrop,reportAirdrop,bountyAirdrop));
    return messageHash
        .toEthSignedMessageHash()
        .recover(signature) == _signer;
  }
}

