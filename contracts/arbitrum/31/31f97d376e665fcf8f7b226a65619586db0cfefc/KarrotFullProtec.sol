//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
     .--------.
    / .------. \
   / /        \ \
   | |        | |
  _| |________| |_
.' |_|        |_| '.
'._____ ____ _____.'
|     .'____'.     |
'.__.'.'    '.'.__.'
'  )$&3b7*3=&*:.  .'
|   '.'.____.'.'   |
'.____'.____.'____.'
'.________________.'


 _______     _ _  ______                      _     
(_______)   | | |(_____ \           _        | |    
 _____ _   _| | | _____) )___ ___ _| |_ _____| |  _ 
|  ___) | | | | ||  ____/ ___) _ (_   _) ___ | |_/ )
| |   | |_| | | || |   | |  | |_| || |_| ____|  _ ( 
|_|   |____/ \_)_)_|   |_|   \___/  \__)_____)_| \_)
                                                    


 */

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./KarrotInterfaces.sol";

/**
FullProtec: The only place to protec your karrots from rabbits
- user's deposited balance is registered on deposit, but the equivalent amount of tokens are burned (avoiding debase)
- this amount is then minted back to the user on withdraw
 */

contract KarrotFullProtec is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IConfig public config;

    struct UserInfo {
        uint256 amount;
        uint256 lockEndedTimestamp;
    }

    uint32 public fullProtecLockDuration = 4 days;
    uint224 public thresholdFullProtecKarrotBalance = 1000000000 * 1e18; //default value to be changed based on token price (1B)
    uint256 public totalStaked;
    address public outputAddress;
    bool public depositsEnabled;

    // Info of each user.
    mapping(address => UserInfo) public userInfo;

    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event SetLockDuration(uint256 fullProtecLockDuration);
    event SetDepositsEnabled(bool enabled);

    error ForwardFailed();
    error CallerIsNotConfig();
    error DepositsDisabled();
    error InvalidAmount();
    error StillLocked();
    error NoOutputAddressSet();
    error InvalidAllowance();

    constructor(address _configManager) {
        config = IConfig(_configManager);
    }

    modifier onlyConfig() {
        if (msg.sender != address(config)) {
            revert CallerIsNotConfig();
        }
        _;
    }

    function deposit(uint256 _amount) external nonReentrant {

        if(!depositsEnabled){
            revert DepositsDisabled();
        }

        if(_amount == 0){
            revert InvalidAmount();
        }

        if(IKarrotsToken(config.karrotsAddress()).allowance(msg.sender, address(this)) < _amount){
            revert InvalidAllowance();
        }

        UserInfo storage user = userInfo[msg.sender];
        user.lockEndedTimestamp = block.timestamp + fullProtecLockDuration;
        address karrotsAddress = config.karrotsAddress();
        IERC20(karrotsAddress).safeTransferFrom(address(msg.sender), address(this), _amount);
        IKarrotsToken(karrotsAddress).burn(_amount);

        totalStaked += _amount;
        user.amount += _amount;
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external nonReentrant {
        if(_amount == 0){
            revert InvalidAmount();
        }
        UserInfo storage user = userInfo[msg.sender];


        if(user.lockEndedTimestamp > block.timestamp){
            revert StillLocked();
        }

        if(user.amount < _amount){
            revert InvalidAmount();
        }

        user.lockEndedTimestamp = block.timestamp + fullProtecLockDuration; //reset lock
        user.amount -= _amount;
        totalStaked -= _amount;
        IKarrotsToken(config.karrotsAddress()).mint(address(msg.sender), _amount);

        emit Withdraw(msg.sender, _amount);
    }

    function getUserStakedAmount(address _user) external view returns (uint256) {
        return userInfo[_user].amount;
    }

    function getTotalStakedAmount() external view returns (uint256) {
        return totalStaked;
    }

    function getIsUserAboveThresholdToAvoidClaimTax(address _user) external view returns (bool) {
        return userInfo[_user].amount >= thresholdFullProtecKarrotBalance;
    }

    //=========================================================================
    // SETTERS
    //=========================================================================

    function setOutputAddress(address _outputAddress) external onlyOwner {
        outputAddress = _outputAddress;
    }

    function openFullProtecDeposits() external onlyConfig {
        depositsEnabled = true;
    }

    function setFullProtecLockDuration(uint32 _lockDuration) external onlyConfig{
        fullProtecLockDuration = _lockDuration;
    }

    function setThresholdFullProtecKarrotBalance(uint224 _threshold) external onlyConfig {
        thresholdFullProtecKarrotBalance = _threshold;
    }

    //=========================================================================
    // WITHDRAWALS
    //=========================================================================

    function withdrawERC20FromContract(address _to, address _token) external onlyOwner {
        bool os = IERC20(_token).transfer(_to, IERC20(_token).balanceOf(address(this)));
        if (!os) {
            revert ForwardFailed();
        }
    }

    function withdrawEthFromContract() external onlyOwner {
        if(outputAddress == address(0)){
            revert NoOutputAddressSet();
        }

        (bool os, ) = payable(outputAddress).call{value: address(this).balance}("");
        
        if (!os) {
            revert ForwardFailed();
        }
    }
}

