// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./PaymentSplitter.sol";
import "./Ownable.sol";
import "./IMarket.sol";

contract teamContract is PaymentSplitter {
  uint256 private immutable teamLength;
  uint constant MAX = 2**256 -1;

  IERC20 public  dsd;
  IERC20 public  labs;
  IERC20 public  prLabs;
  IERC20 public usdc;
  address public  market;
  mapping(address => bool) isTeam;

  modifier onlyTeam() {
    require(isTeam[msg.sender] , "Just temmates");
    _;
  }

  constructor(address[] memory _team, uint256[] memory _teamShares, IERC20 _dsd, IERC20 _labs, IERC20 _prLabs, IERC20 _usdc)
    PaymentSplitter(_team, _teamShares)
  {
    teamLength = _team.length;
    for (uint i = 0; i < _team.length; i++) {
      isTeam[_team[i]] = true;
    }
    
    dsd = _dsd;
    labs = _labs;
    prLabs = _prLabs;
    usdc = _usdc;
  }



function setMarket(address _market) external onlyTeam {
  market = _market;
  dsd.approve(market,MAX);
  labs.approve(market,MAX);
  prLabs.approve(market,MAX);
}
  function release(IERC20 token, address account) public override   {
    require(true, "lol");
  }
  function release( address payable account) public  override {
    require(true, "lol");
  }
  function _release(IERC20 token, address account) internal   {
   super.release( token,  account);
  }
  function _release(address payable account) internal   {
     super.release(  account);
  }
  function releaseAllEth() external {
      unchecked {
    for (uint256 i = 0; i < teamLength; ) {
      _release(payable(payee(i)));
        ++i;
      }
    }
  }
  function releaseAllErc20(IERC20 _token) public onlyTeam {
      unchecked {
    for (uint256 i = 0; i < teamLength; ) {
      _release(_token, payee(i));
        ++i;
      }
    }
  }

  function releaseAllUsdc() external onlyTeam {
    releaseAllErc20(usdc);
  }

  function realize() external onlyTeam{
    uint dsdBal = dsd.balanceOf(address(this));
    uint prLabsBal = prLabs.balanceOf(address(this));
    (, uint worth) = IMarket(market).estimateRealize(prLabsBal, address(dsd));
    uint ratioX1e4 = dsdBal < worth ?  1e4 * dsdBal / worth : 1e4;
    uint prLabsToRealize = prLabsBal * ratioX1e4 / 1e4;
    IMarket(market).realize(prLabsToRealize, address(dsd), MAX);
  }


  function sell() external onlyTeam {
    IMarket(market).sell(labs.balanceOf(address(this)), address(usdc), 0);
  }
    function buy() external onlyTeam {
    IMarket(market).buy(address(dsd), dsd.balanceOf(address(this)), 0);
  }
}

