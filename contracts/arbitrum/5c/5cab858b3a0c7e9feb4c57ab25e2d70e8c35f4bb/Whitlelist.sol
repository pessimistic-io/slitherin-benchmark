// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./ReentrancyGuard.sol";
import { Governable } from "./Governable.sol";
import { IERC20 } from "./IERC20.sol";

contract Whitlelist is ReentrancyGuard, Governable {
    bool public isDeposit;
    bool public isClaimWhitelist;
    bool public isClaimAirdropToken;

    uint256 public amountDeposit = 5 * 10 ** 18;
    uint256 public totalDeposit;
    uint256 public totalClaim;
    uint256 public totalAirdrop;
    uint256 public amountAirdrop = 5 * 10 ** 18;
    address public tokenDeposit;
    address public tokenGov;

    mapping (address => uint256) public depositUsers;
    mapping (address => bool) public isClaimTokenDeposit;
    mapping (address => bool) public isClaimTokenGov;

    event Deposit(address indexed account, uint256 amount);
    event ClaimWhitlelist(address indexed account, uint256 amount);
    event ClaimAirdropToken(address indexed account, uint256 amount);

    constructor(address _tokenDeposit, address _tokenGov) {
      tokenDeposit = _tokenDeposit;
      tokenGov = _tokenGov;
    }

    function setWhitlelistStatus(bool _isDeposit, bool _isClaimWhitelist, bool _isClaimAirdropToken) external onlyGov {
      isDeposit = _isDeposit;
      isClaimWhitelist = _isClaimWhitelist;
      isClaimAirdropToken = _isClaimAirdropToken;
    }
    
    function setTokens(address _tokenDeposit, address _tokenGov) external onlyGov {
      tokenDeposit = _tokenDeposit;
      tokenGov = _tokenGov;
    }

    function setTokensAmount(uint256 _amountDeposit, uint256 _amountAirdrop) external onlyGov {
      amountDeposit = _amountDeposit;
      amountAirdrop = _amountAirdrop;
    }

    function deposit(uint256 _amount) external {
      require(isDeposit, "Whitlelist: deposit not active");
      require(_amount == amountDeposit, "Whitlelist: amount equal amountDeposit");
      require(depositUsers[msg.sender] == 0, "Whitlelist: user already in whitlelist");

      IERC20(tokenDeposit).transferFrom(msg.sender, address(this), amountDeposit);
      depositUsers[msg.sender] = amountDeposit;
      totalDeposit += amountDeposit;

      emit Deposit(msg.sender, amountDeposit);
    }

    function withDrawnFund(uint256 _amount) external onlyGov {
      IERC20(tokenDeposit).transfer(msg.sender, _amount);
    }

    function claimWhitlelist() external {
      require(isClaimWhitelist, "Whitlelist: claim token not active");
      require(depositUsers[msg.sender] > 0, "Whitlelist: user don't have balance");
      require(!isClaimTokenDeposit[msg.sender], "Whitlelist: user already claim token");
      require(IERC20(tokenDeposit).balanceOf(address(this)) >= amountDeposit, "Whitlelist: not enough balance");
      
      IERC20(tokenDeposit).transfer(msg.sender, amountDeposit);
      isClaimTokenDeposit[msg.sender] = true;
      totalClaim += amountDeposit;
      emit ClaimWhitlelist(msg.sender, amountDeposit);
    }

    function claimAirdropToken() external {
      require(isClaimAirdropToken, "Whitlelist: claim token not active");
      require(depositUsers[msg.sender] > 0, "Whitlelist: user don't have balance");
      require(!isClaimTokenGov[msg.sender], "Whitlelist: user already claim token");
      require(IERC20(tokenGov).balanceOf(address(this)) >= amountAirdrop, "Whitlelist: not enough balance");

      IERC20(tokenGov).transfer(msg.sender, amountAirdrop);
      isClaimTokenGov[msg.sender] = true;
      totalAirdrop += amountAirdrop;

      emit ClaimAirdropToken(msg.sender, amountAirdrop);
    }

    /**
     * @notice Allows the owner to recover tokens sent to the contract by mistake
     * @param _token: token address
     * @dev Callable by owner
     */
    function recoverFungibleTokens(address _token) external onlyGov {
        uint256 amountToRecover = IERC20(_token).balanceOf(address(this));
        require(amountToRecover != 0, "Operations: No token to recover");

        IERC20(_token).transfer(address(msg.sender), amountToRecover);
    }
}
