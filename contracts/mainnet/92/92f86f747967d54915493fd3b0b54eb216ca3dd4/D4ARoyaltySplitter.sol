// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "./OwnableUpgradeable.sol";
import "./Clones.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ID4ASetting.sol";
import "./ID4AProtocol.sol";
import "./ID4ARoyaltySplitterFactory.sol";
import "./TokenClaimer.sol";
import "./IWETH.sol";

contract D4ARoyaltySplitter is Initializable, OwnableUpgradeable, TokenClaimer{
  ID4ASetting public setting;
  address public addr1;
  address public addr2;
  bytes32 public proj_id;
  uint256 public w1;
  uint256 public w2;

  using SafeERC20 for IERC20;

  function initialize(ID4ASetting _setting, address _addr1, uint256 _w1, address _addr2, uint256 _w2) public initializer{
    __Ownable_init();
    setting = _setting;
    addr1 = _addr1;
    w1 = _w1;
    addr2 = _addr2;
    w2 = _w2;
  }

  function set(uint256 _w1, uint256 _w2) public onlyOwner{
    w1 = _w1;
    w2 = _w2;
  }

  function claimStdTokens(address _token, address payable to) public onlyOwner{
    _claimStdTokens(_token, to);
  }

  function claimERC20(address token) external {
    uint256 balance = IERC20(token).balanceOf(address(this));
    uint256 v1 = balance * w1/(w1 + w2);
    uint256 v2 = balance - v1;

    if(v1 != 0){
      IERC20(token).safeTransfer(addr1, v1);
    }
    if(v2 != 0){
      IERC20(token).safeTransfer(addr2, v2);
      //(succ, ) = setting.owner_proxy().ownerOf(proj_id).call{value:v2}("");
    }
  }

  function claimWETH() external {
    IWETH token = IWETH(setting.WETH());
    token.withdraw(token.balanceOf(address(this)));
  }

  fallback() external payable{
    uint256 v1 = msg.value * w1/(w1 + w2);
    uint256 v2 = msg.value - v1;

    bool succ;
    if(v1 != 0){
      (succ, ) = addr1.call{value:v1}("");
      require(succ, "split ether failed");
    }
    if(v2 != 0){
      //(succ, ) = setting.owner_proxy().ownerOf(proj_id).call{value:v2}("");
      (succ, ) = addr2.call{value:v2}("");
      require(succ, "split ether failed");
    }
  }
}

contract D4ARoyaltySplitterFactory is ID4ARoyaltySplitterFactory{
  using Clones for address;
  D4ARoyaltySplitter public impl;
  event NewD4ARoyaltySplitter(address addr);
  constructor(){
    impl = new D4ARoyaltySplitter();
  }

  function createD4ARoyaltySplitter(address setting, address addr1, uint256 w1, address addr2, uint256 w2) public returns(address){
    D4ARoyaltySplitter t = D4ARoyaltySplitter(payable(address(impl).clone()));
    t.initialize(ID4ASetting(setting), addr1, w1, addr2, w2);
    t.transferOwnership(msg.sender);

    emit NewD4ARoyaltySplitter(address(t));
    return address(t);
  }
}

